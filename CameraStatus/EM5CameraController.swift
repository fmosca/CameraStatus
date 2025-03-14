import Foundation
import CoreBluetooth

protocol CameraController {
    func powerOn(camera: Camera, centralManager: CBCentralManager, completion: @escaping (Bool, String) -> Void)
    func canPowerOn(camera: Camera) -> Bool
}

class EM5CameraController: NSObject, CameraController, CBPeripheralDelegate {
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var completion: ((Bool, String) -> Void)?
    private var isPoweringOn = false
    private var connectionAttempts = 0
    private var maxConnectionAttempts = 5
    private var retryTimer: Timer?
    private var timeoutTimer: Timer?
    private var currentCharacteristic: CBCharacteristic?
    
    // Known working characteristic UUID for EM5mkIII
    private let workingCharacteristicUUID = "82f949b4-f5dc-4cf3-ab3c-fd9fd4017b68"
    
    // Passcode for EM5mkIII
    private let cameraPasscode = "258967"
    
    func canPowerOn(camera: Camera) -> Bool {
        return camera.name.contains("BJ8A15412") || camera.name.contains("E-M5MKIII")
    }
    
    func powerOn(camera: Camera, centralManager: CBCentralManager, completion: @escaping (Bool, String) -> Void) {
        // Reset state
        self.centralManager = centralManager
        self.completion = completion
        self.isPoweringOn = true
        self.connectionAttempts = 0
        
        // Start the connection process
        startConnectionAttempt(camera: camera)
    }
    
    private func startConnectionAttempt(camera: Camera) {
        guard let centralManager = centralManager else { return }
        
        connectionAttempts += 1
        
        // Update status with attempt number
        let statusMessage = connectionAttempts > 1
            ? "Connecting to camera (attempt \(connectionAttempts)/\(maxConnectionAttempts))..."
            : "Connecting to camera..."
        
        completion?(false, statusMessage)
        
        print("Starting connection attempt \(connectionAttempts)/\(maxConnectionAttempts) to camera \(camera.name)")
        
        // Need to discover the camera again to connect to it
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        
        // Set a timeout for this attempt
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            self.centralManager?.stopScan()
            
            if self.connectionAttempts < self.maxConnectionAttempts {
                print("Attempt \(self.connectionAttempts) timed out, will retry...")
                
                // Calculate backoff time (exponential with a cap)
                let backoffTime = min(1.0 * Double(self.connectionAttempts), 5.0)
                
                self.completion?(false, "Connection attempt \(self.connectionAttempts) failed, retrying in \(Int(backoffTime))s...")
                
                // Schedule retry with backoff
                self.retryTimer?.invalidate()
                self.retryTimer = Timer.scheduledTimer(withTimeInterval: backoffTime, repeats: false) { [weak self] _ in
                    self?.startConnectionAttempt(camera: camera)
                }
            } else {
                print("All \(self.maxConnectionAttempts) attempts failed")
                self.completion?(true, "Failed to connect after \(self.maxConnectionAttempts) attempts")
                self.cleanUp()
            }
        }
    }
    
    // Calculate checksum for camera commands
    private func calculateChecksum(initialValue: UInt8, bytesToSum: [UInt8]) -> UInt8 {
        var checksum: Int = Int(initialValue)
        for byte in bytesToSum {
            checksum += Int(byte)
        }
        return UInt8(checksum & 0xFF) // Ensure 8-bit value
    }
    
    // Generate passcode bytes for authentication
    private func generatePasscodeBytes() -> Data {
        // Header bytes
        let header: [UInt8] = [0x01, 0x01, 0x09, 0x0c, 0x01, 0x02]
        
        // Convert passcode to bytes
        let passcodeBytes = cameraPasscode.compactMap { UInt8($0.asciiValue ?? 0) }
        
        // Calculate checksum: 0x0c + 0x01 + 0x02 + passcode bytes
        let checksumInput: [UInt8] = [0x01, 0x02] + passcodeBytes
        let checksum = calculateChecksum(initialValue: 0x0c, bytesToSum: checksumInput)
        
        // Combine all parts
        let result: [UInt8] = header + passcodeBytes + [checksum, 0x00]
        return Data(result)
    }
    
    // Generate power-on command bytes
    private func generatePowerOnBytes() -> Data {
        // Fixed power-on sequence
        let powerOnSequence: [UInt8] = [0x01, 0x01, 0x04, 0x0f, 0x01, 0x01, 0x02, 0x13, 0x00]
        return Data(powerOnSequence)
    }
    
    // Send authentication and power on commands
    private func sendAuthenticationAndPowerOn(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        // Generate authentication data
        let authData = generatePasscodeBytes()
        print("Sending authentication: \(authData.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
        
        // Write authentication data
        peripheral.writeValue(authData, for: characteristic, type: .withResponse)
        
        // Wait for processing, then send power-on
        completion?(false, "Authentication sent, sending power-on command...")
        
        // Wait 2.5 seconds before sending power-on command
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            
            // Generate power-on data
            let powerOnData = self.generatePowerOnBytes()
            print("Sending power-on: \(powerOnData.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
            
            // Write power-on data
            peripheral.writeValue(powerOnData, for: characteristic, type: .withResponse)
            
            self.completion?(false, "Power on command sent successfully!")
            
            // Disconnect after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.centralManager?.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    // Clean up resources
    private func cleanUp() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        retryTimer?.invalidate()
        retryTimer = nil
        peripheral = nil
        centralManager = nil
        completion = nil
    }
    
    // MARK: - Connection Handlers
    
    func didFindPeripheral(_ peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        // Check if this is the EM5 camera we're looking for
        if let name = peripheral.name,
           (name.contains("BJ8A15412") || name.contains("E-M5MKIII")) {
            
            completion?(false, "Camera found, connecting...")
            
            print("Found EM5 camera for power on, connecting...")
            self.peripheral = peripheral
            peripheral.delegate = self
            centralManager?.stopScan()
            centralManager?.connect(peripheral, options: nil)
            timeoutTimer?.invalidate() // Cancel timeout timer once we find the device
        }
    }
    
    func didConnect(peripheral: CBPeripheral) {
        print("Connected to EM5 camera: \(peripheral.name ?? peripheral.identifier.uuidString)")
        
        // Cancel any pending retry timers
        retryTimer?.invalidate()
        timeoutTimer?.invalidate()
        
        completion?(false, "Connected, discovering services...")
        
        // Start discovering services
        peripheral.discoverServices(nil)
    }
    
    func didFailToConnect(peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to EM5 camera: \(error?.localizedDescription ?? "Unknown error")")
        
        if connectionAttempts < maxConnectionAttempts {
            print("Connection failed on attempt \(connectionAttempts), will retry...")
            
            // Calculate backoff time
            let backoffTime = min(0.5 * Double(connectionAttempts), 2.0)
            
            completion?(false, "Connection failed, retrying in \(Int(backoffTime))s...")
            
            // Schedule retry with backoff
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: backoffTime, repeats: false) { [weak self] _ in
                guard let self = self, let camera = self.peripheral else { return }
                self.startConnectionAttempt(camera: Camera(
                    id: camera.identifier.uuidString,
                    name: camera.name ?? "EM5 Camera",
                    isAvailable: true,
                    rssi: 0,
                    lastSeen: Date()
                ))
            }
        } else {
            completion?(true, "Failed to connect after \(maxConnectionAttempts) attempts")
            cleanUp()
        }
    }
    
    func didDisconnect(peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from EM5 camera: \(peripheral.name ?? peripheral.identifier.uuidString)")
        
        // If we've completed the power-on sequence, this is expected
        if let completion = completion {
            // Get the current status from the last completion call
            let statusBeforeDisconnect = Mirror(reflecting: self).children
                .first(where: { $0.label == "completion" })?
                .value as? ((Bool, String) -> Void)
            
            if statusBeforeDisconnect != nil {
                completion(true, "Camera powered on! WiFi should be available soon.")
            } else if connectionAttempts == 1 {
                // If we disconnected unexpectedly during first attempt (common with EM5)
                print("First connection attempt disconnected unexpectedly - this is normal for EM5, retrying...")
                
                self.completion?(false, "Initial connection established, retrying...")
                
                // Wait a moment before retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, let camera = self.peripheral else { return }
                    self.startConnectionAttempt(camera: Camera(
                        id: camera.identifier.uuidString,
                        name: camera.name ?? "EM5 Camera",
                        isAvailable: true,
                        rssi: 0,
                        lastSeen: Date()
                    ))
                }
            } else if connectionAttempts >= maxConnectionAttempts {
                // If we've exhausted our retries
                completion(true, "Disconnected unexpectedly after \(connectionAttempts) attempts")
                cleanUp()
            } else {
                // Otherwise try again
                print("Unexpected disconnect on attempt \(connectionAttempts), retrying...")
                
                completion(false, "Disconnected, retrying...")
                
                // Wait a moment before retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, let camera = self.peripheral else { return }
                    self.startConnectionAttempt(camera: Camera(
                        id: camera.identifier.uuidString,
                        name: camera.name ?? "EM5 Camera",
                        isAvailable: true,
                        rssi: 0,
                        lastSeen: Date()
                    ))
                }
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate methods
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            completion?(true, "Error discovering services")
            cleanUp()
            return
        }
        
        guard let services = peripheral.services, !services.isEmpty else {
            print("No services found")
            completion?(true, "No services found on camera")
            cleanUp()
            return
        }
        
        completion?(false, "Discovering characteristics...")
        
        // Discover characteristics for each service
        for service in services {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            completion?(true, "Error discovering characteristics")
            cleanUp()
            return
        }
        
        guard let characteristics = service.characteristics, !characteristics.isEmpty else {
            print("No characteristics found for service \(service.uuid)")
            return
        }
        
        // Look for our target characteristic or any writable characteristics
        var foundWorkingCharacteristic = false
        var writableCharacteristics: [CBCharacteristic] = []
        
        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic.uuid), properties: \(characteristic.properties)")
            
            // Check if this is our known working characteristic
            if characteristic.uuid.uuidString.lowercased() == workingCharacteristicUUID.lowercased() {
                print("Found our target characteristic!")
                foundWorkingCharacteristic = true
                currentCharacteristic = characteristic
                break
            }
            
            // Otherwise, collect all writable characteristics
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writableCharacteristics.append(characteristic)
            }
        }
        
        // If we found our target characteristic, use it
        if foundWorkingCharacteristic, let characteristic = currentCharacteristic {
            completion?(false, "Sending authentication...")
            
            // Send authentication
            sendAuthenticationAndPowerOn(peripheral: peripheral, characteristic: characteristic)
        }
        // If not, try the first writable characteristic
        else if !writableCharacteristics.isEmpty {
            print("No known working characteristic found, trying first writable characteristic")
            currentCharacteristic = writableCharacteristics.first
            
            completion?(false, "Sending authentication (experimental)...")
            
            if let characteristic = currentCharacteristic {
                sendAuthenticationAndPowerOn(peripheral: peripheral, characteristic: characteristic)
            }
        }
        else {
            print("No writable characteristics found")
            completion?(true, "No suitable characteristics found")
            cleanUp()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error writing characteristic: \(error.localizedDescription)")
            completion?(true, "Error sending command: \(error.localizedDescription)")
            cleanUp()
        } else {
            print("Successfully wrote value to characteristic")
        }
    }
}
