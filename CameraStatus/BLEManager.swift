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
    private var foundAllCameras = false
    
    private var centralManager: CBCentralManager!
    private var scanTimer: Timer?
    private var timeoutTimer: Timer?
    
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
    
    // Clean up when object is deallocated
    deinit {
        stopPeriodicScanning()
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
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

        // Check if this is a known camera by name or UUID
        if isKnownCamera(peripheral: peripheral) {
            let name = peripheral.name ?? "Camera (\(peripheralId.suffix(6)))"
            print("Found camera: \(name) (UUID: \(peripheralId), RSSI: \(RSSI.intValue))")
            
            // Use the dictionary to ensure uniqueness
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
}
