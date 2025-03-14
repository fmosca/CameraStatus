import Foundation
import CoreBluetooth

class BLEManager: NSObject, ObservableObject {
    @Published private var cameraDict: [String: Camera] = [:]
    var cameras: [Camera] {
        Array(cameraDict.values)
    }
    
    @Published var isScanning = false
    @Published var bluetoothState: String = "Unknown"
    @Published var isBluetoothReady = false
    @Published var isPoweringOn = false
    @Published var powerOnStatus: String = ""
    
    private var foundAllCameras = false
    private var currentPeripheral: CBPeripheral?
    private var currentCharacteristic: CBCharacteristic?
    private var currentCameraForPowerOn: Camera?
    private var connectionAttempts = 0
    private var maxConnectionAttempts = 5
    
    private var centralManager: CBCentralManager!
    private var scanTimer: Timer?
    private var timeoutTimer: Timer?
    private var retryTimer: Timer?
    
    // Known working characteristic UUID for EM5mkIII from Python script
    private let workingCharacteristicUUID = "82f949b4-f5dc-4cf3-ab3c-fd9fd4017b68"
    
    // Passcode for EM5mkIII from Python script
    private let cameraPasscode = "258967"
    
    // List of UUIDs for your cameras
    private let knownCameraUUIDs = [
        "10763D9D-22B1-A168-8B62-2CA083E3BE4F"  // Your GR_5A9E88 camera
        // Add more camera UUIDs here as you discover them
    ]
    
    // The camera names to look for
    private let knownCameraNames = [
        "BJ8A15412",         // EM5mkIII camera from Python script
        "E-M5MKIII-P-BJ8A15412", // Alternative name format
        "GR_5A9E88"          // Your existing camera
    ]
    
    override init() {
        super.init()
        // Initialize but don't start scanning yet
        centralManager = CBCentralManager(delegate: self, queue: nil)
        print("BLEManager initialized")
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth not available: \(centralManager.state.rawValue)")
            bluetoothState = "Powered Off"
            isBluetoothReady = false
            return
        }
        
        isScanning = true
        foundAllCameras = false
        print("Starting scan for cameras with extended duration...")
        
        // Use CBCentralManagerScanOptionAllowDuplicatesKey: true to catch intermittent advertisements
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
        )
        
        // Set a timeout timer to stop scanning after 25 seconds
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
    }
    
    func stopScanning() {
        if isScanning {
            centralManager.stopScan()
            isScanning = false
            timeoutTimer?.invalidate()
            print("Scan stopped. Found \(cameras.count) cameras")
        }
    }
    
    // Start periodic scanning
    func startPeriodicScanning(interval: TimeInterval = 60.0) {
        // Invalidate any existing timer
        scanTimer?.invalidate()
        
        // If Bluetooth is not ready, just set the flag and return
        guard isBluetoothReady else {
            print("Bluetooth not ready, will start scanning when ready")
            return
        }
        
        // Start the first scan immediately
        startScanning()
        
        // Set up timer for periodic scanning
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            print("Starting periodic scan")
            self?.startScanning()
        }
    }
    
    // Stop periodic scanning
    func stopPeriodicScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        stopScanning()
    }
    
    // Helper function to check if a peripheral is a known camera by name
    private func isKnownCamera(peripheral: CBPeripheral) -> Bool {
        guard let name = peripheral.name else {
            return isKnownCamera(peripheralId: peripheral.identifier.uuidString)
        }
        
        // Check if the name contains any of our known camera names
        for cameraName in knownCameraNames {
            if name.contains(cameraName) {
                return true
            }
        }
        
        return isKnownCamera(peripheralId: peripheral.identifier.uuidString)
    }
    
    // Helper function to check if a peripheral is a known camera
    private func isKnownCamera(peripheralId: String) -> Bool {
        return knownCameraUUIDs.contains(peripheralId)
    }
    
    // Function to power on the EM5mkIII camera
    func powerOnCamera(camera: Camera) {
        // Make sure we're not already trying to power on a camera
        guard !isPoweringOn else {
            print("Already in the process of powering on a camera")
            return
        }
        
        // Reset status
        isPoweringOn = true
        powerOnStatus = "Connecting to camera..."
        connectionAttempts = 0
        currentCameraForPowerOn = camera
        
        // Check if this is an EM5mkIII by checking the name
        guard camera.name.contains("BJ8A15412") || camera.name.contains("E-M5MKIII") else {
            powerOnStatus = "Not an Olympus EM5 camera"
            isPoweringOn = false
            return
        }
        
        // Start the connection attempt with retry mechanism
        startConnectionAttempt()
    }
    
    // Start or retry connection attempt
    private func startConnectionAttempt() {
        guard let camera = currentCameraForPowerOn, isPoweringOn else { return }
        
        connectionAttempts += 1
        
        // Update status with attempt number if not the first attempt
        if connectionAttempts > 1 {
            DispatchQueue.main.async {
                self.powerOnStatus = "Connecting to camera (attempt \(self.connectionAttempts)/\(self.maxConnectionAttempts))..."
            }
        }
        
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
            
            self.centralManager.stopScan()
            
            if self.connectionAttempts < self.maxConnectionAttempts {
                print("Attempt \(self.connectionAttempts) timed out, will retry...")
                
                // Calculate backoff time (exponential with a cap)
                let backoffTime = min(1.0 * Double(self.connectionAttempts), 5.0)
                
                DispatchQueue.main.async {
                    self.powerOnStatus = "Connection attempt \(self.connectionAttempts) failed, retrying in \(Int(backoffTime))s..."
                }
                
                // Schedule retry with backoff
                self.retryTimer?.invalidate()
                self.retryTimer = Timer.scheduledTimer(withTimeInterval: backoffTime, repeats: false) { [weak self] _ in
                    self?.startConnectionAttempt()
                }
            } else {
                print("All \(self.maxConnectionAttempts) attempts failed")
                DispatchQueue.main.async {
                    self.isPoweringOn = false
                    self.powerOnStatus = "Failed to connect after \(self.maxConnectionAttempts) attempts"
                }
            }
        }
    }
    
    // Calculate checksum for camera commands (based on Python script)
    private func calculateChecksum(initialValue: UInt8, bytesToSum: [UInt8]) -> UInt8 {
        var checksum: Int = Int(initialValue)
        for byte in bytesToSum {
            checksum += Int(byte)
        }
        return UInt8(checksum & 0xFF) // Ensure 8-bit value
    }
    
    // Generate passcode bytes for authentication (based on Python script)
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
    
    // Generate power-on command bytes (based on Python script)
    private func generatePowerOnBytes() -> Data {
        // Fixed power-on sequence from documentation in Python script
        let powerOnSequence: [UInt8] = [0x01, 0x01, 0x04, 0x0f, 0x01, 0x01, 0x02, 0x13, 0x00]
        return Data(powerOnSequence)
    }
    
    // Clean up when object is deallocated
    deinit {
        stopPeriodicScanning()
    }
}

// MARK: - CBCentralManagerDelegate & CBPeripheralDelegate
extension BLEManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            bluetoothState = "Powered On"
            isBluetoothReady = true
            // Start periodic scanning now that Bluetooth is ready
            startPeriodicScanning()
        case .poweredOff:
            print("Bluetooth is powered off")
            bluetoothState = "Powered Off"
            isBluetoothReady = false
            DispatchQueue.main.async {
                self.stopPeriodicScanning()
                self.cameraDict.removeAll()
            }
        case .resetting:
            print("Bluetooth is resetting")
            bluetoothState = "Resetting"
            isBluetoothReady = false
        case .unauthorized:
            print("Bluetooth is unauthorized")
            bluetoothState = "Unauthorized"
            isBluetoothReady = false
        case .unsupported:
            print("Bluetooth is unsupported")
            bluetoothState = "Unsupported"
            isBluetoothReady = false
        case .unknown:
            print("Bluetooth state is unknown")
            bluetoothState = "Unknown"
            isBluetoothReady = false
        @unknown default:
            print("Unknown Bluetooth state")
            bluetoothState = "Unknown State"
            isBluetoothReady = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let peripheralId = peripheral.identifier.uuidString

        // For debugging - log all discovered devices with their names
        if let name = peripheral.name {
            print("Discovered device: \(name) (UUID: \(peripheralId), RSSI: \(RSSI.intValue))")
        }

        // If we're powering on and this is the camera we're looking for
        if isPoweringOn && currentCameraForPowerOn != nil {
            if let name = peripheral.name,
               (name.contains("BJ8A15412") || name.contains("E-M5MKIII")) {
                DispatchQueue.main.async {
                    self.powerOnStatus = "Camera found, connecting..."
                }
                
                print("Found EM5 camera for power on, connecting...")
                self.currentPeripheral = peripheral
                peripheral.delegate = self
                self.centralManager.stopScan()
                self.centralManager.connect(peripheral, options: nil)
                return
            }
        }
        // Otherwise check if this is a camera for tracking
        else if isKnownCamera(peripheral: peripheral) {
            let name = peripheral.name ?? "Camera (\(peripheralId.suffix(6)))"
            print("Found camera: \(name) (UUID: \(peripheralId), RSSI: \(RSSI.intValue))")
            
            // Add to our camera list for display
            DispatchQueue.main.async {
                // Create or update the camera in our dictionary
                let camera = Camera(
                    id: peripheralId,
                    name: name,
                    isAvailable: true,
                    rssi: RSSI.intValue,
                    lastSeen: Date()
                )
                
                // This automatically replaces any existing entry with the same key
                self.cameraDict[peripheralId] = camera
                
                // Stop scanning if we've found both cameras (using names to check, not UUIDs)
                let foundCameraNames = Set(self.cameras.map { $0.name })
                let foundNameCount = self.knownCameraNames.filter { cameraName in
                    foundCameraNames.contains { $0.contains(cameraName) }
                }.count
                
                // If we have at least 2 cameras or found all our named cameras, stop scanning
                if self.cameras.count >= 2 || foundNameCount >= self.knownCameraNames.count {
                    print("All cameras found, stopping scan")
                    self.stopScanning()
                }
            }
        }
    }
    
    // Called when we successfully connect to a peripheral
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? peripheral.identifier.uuidString)")
        
        // Cancel any pending retry timers
        retryTimer?.invalidate()
        timeoutTimer?.invalidate()
        
        if isPoweringOn {
            DispatchQueue.main.async {
                self.powerOnStatus = "Connected, discovering services..."
            }
            
            // Start discovering services
            peripheral.discoverServices(nil)
        }
    }
    
    // Called when connection fails
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
        
        if isPoweringOn {
            if connectionAttempts < maxConnectionAttempts {
                print("Connection failed on attempt \(connectionAttempts), will retry...")
                
                // Calculate backoff time (linear with a cap)
                let backoffTime = min(0.5 * Double(connectionAttempts), 2.0)
                
                DispatchQueue.main.async {
                    self.powerOnStatus = "Connection failed, retrying in \(Int(backoffTime))s..."
                }
                
                // Schedule retry with backoff
                retryTimer?.invalidate()
                retryTimer = Timer.scheduledTimer(withTimeInterval: backoffTime, repeats: false) { [weak self] _ in
                    self?.startConnectionAttempt()
                }
            } else {
                DispatchQueue.main.async {
                    self.isPoweringOn = false
                    self.powerOnStatus = "Failed to connect after \(self.maxConnectionAttempts) attempts"
                }
            }
        }
    }
    
    // Called when disconnected from a peripheral
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? peripheral.identifier.uuidString)")
        
        if isPoweringOn {
            // If we've completed the power-on sequence, this is expected
            if self.powerOnStatus == "Power on command sent successfully!" {
                DispatchQueue.main.async {
                    self.powerOnStatus = "Camera powered on! WiFi should be available soon."
                    
                    // Reset state after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        self.isPoweringOn = false
                    }
                }
            }
            // If we disconnected unexpectedly during first attempt (common with EM5)
            else if connectionAttempts == 1 {
                print("First connection attempt disconnected unexpectedly - this is normal for EM5, retrying...")
                
                DispatchQueue.main.async {
                    self.powerOnStatus = "Initial connection established, retrying..."
                }
                
                // Wait a moment before retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startConnectionAttempt()
                }
            }
            // If we've exhausted our retries
            else if connectionAttempts >= maxConnectionAttempts {
                DispatchQueue.main.async {
                    self.isPoweringOn = false
                    self.powerOnStatus = "Disconnected unexpectedly after \(self.connectionAttempts) attempts"
                }
            }
            // Otherwise try again
            else {
                print("Unexpected disconnect on attempt \(connectionAttempts), retrying...")
                
                DispatchQueue.main.async {
                    self.powerOnStatus = "Disconnected, retrying..."
                }
                
                // Wait a moment before retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startConnectionAttempt()
                }
            }
        }
    }
    
    // Called when services are discovered
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isPoweringOn else { return }
        
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isPoweringOn = false
                self.powerOnStatus = "Error discovering services"
            }
            return
        }
        
        guard let services = peripheral.services, !services.isEmpty else {
            print("No services found")
            DispatchQueue.main.async {
                self.isPoweringOn = false
                self.powerOnStatus = "No services found on camera"
            }
            return
        }
        
        DispatchQueue.main.async {
            self.powerOnStatus = "Discovering characteristics..."
        }
        
        // Discover characteristics for each service
        for service in services {
            print("Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    // Called when characteristics are discovered
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard isPoweringOn else { return }
        
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isPoweringOn = false
                self.powerOnStatus = "Error discovering characteristics"
            }
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
            DispatchQueue.main.async {
                self.powerOnStatus = "Sending authentication..."
            }
            
            // Send authentication
            sendAuthenticationAndPowerOn(peripheral: peripheral, characteristic: characteristic)
        }
        // If not, try the first writable characteristic
        else if !writableCharacteristics.isEmpty {
            print("No known working characteristic found, trying first writable characteristic")
            currentCharacteristic = writableCharacteristics.first
            
            DispatchQueue.main.async {
                self.powerOnStatus = "Sending authentication (experimental)..."
            }
            
            if let characteristic = currentCharacteristic {
                sendAuthenticationAndPowerOn(peripheral: peripheral, characteristic: characteristic)
            }
        }
        else {
            print("No writable characteristics found")
            DispatchQueue.main.async {
                self.isPoweringOn = false
                self.powerOnStatus = "No suitable characteristics found"
            }
        }
    }
    
    // Send authentication and power on commands
    private func sendAuthenticationAndPowerOn(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        // Generate authentication data
        let authData = generatePasscodeBytes()
        print("Sending authentication: \(authData.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
        
        // Write authentication data
        peripheral.writeValue(authData, for: characteristic, type: .withResponse)
        
        // Wait for processing, then send power-on
        DispatchQueue.main.async {
            self.powerOnStatus = "Authentication sent, sending power-on command..."
        }
        
        // Wait 2.5 seconds before sending power-on command (based on Python script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // Generate power-on data
            let powerOnData = self.generatePowerOnBytes()
            print("Sending power-on: \(powerOnData.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
            
            // Write power-on data
            peripheral.writeValue(powerOnData, for: characteristic, type: .withResponse)
            
            DispatchQueue.main.async {
                self.powerOnStatus = "Power on command sent successfully!"
            }
            
            // Disconnect after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    // Called when a characteristic is written
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error writing characteristic: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isPoweringOn = false
                self.powerOnStatus = "Error sending command: \(error.localizedDescription)"
            }
        } else {
            print("Successfully wrote value to characteristic")
        }
    }
}
