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
    
    private var centralManager: CBCentralManager!
    private var scanTimer: Timer?
    private var timeoutTimer: Timer?
    
    // List of UUIDs for your cameras
    private let knownCameraUUIDs = [
        "10763D9D-22B1-A168-8B62-2CA083E3BE4F"  // Your GR_5A9E88 camera
        // Add more camera UUIDs here as you discover them
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
        print("Starting scan for cameras...")
        
        // Start scanning
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // Set a timeout timer to stop scanning if nothing is found within 10 seconds
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
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
    func startPeriodicScanning(interval: TimeInterval = 30.0) {
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
        let name = peripheral.name ?? "Camera (\(peripheralId.suffix(6)))"
        
        // Only process devices that match our known camera UUIDs
        if isKnownCamera(peripheralId: peripheralId) {
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
                
                // Stop scanning once we've found all our cameras
                if self.cameraDict.count >= self.knownCameraUUIDs.count {
                    print("All cameras found, stopping scan")
                    self.stopScanning()
                }
            }
        }
    }
}
