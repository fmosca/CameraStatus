import Foundation
import CoreBluetooth

class BLEManager: NSObject, ObservableObject, ScannerDelegate {
    @Published private var cameraDict: [String: Camera] = [:]
    var cameras: [Camera] {
        Array(cameraDict.values)
    }
    @Published var isPoweringOn: Bool = false
    
    @Published var isScanning = false
    @Published var bluetoothState: String = "Unknown"
    @Published var isBluetoothReady = false
    private var foundAllCameras = false
    
    private var centralManager: CBCentralManager!
    private var scanner: BluetoothScanner!
    
    override init() {
        super.init()
        // Initialize but don't start scanning yet
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // Set up scanner with this manager as delegate
        scanner = BluetoothScanner(centralManager: centralManager)
        scanner.delegate = self
        
        // Register camera identifiers
        scanner.registerCameraIdentifier(EM5CameraIdentifier())
        scanner.registerCameraIdentifier(RicohCameraIdentifier())
        
        print("BLEManager initialized")
    }
    
    func startScanning() {
        if isBluetoothReady {
            isScanning = true
            foundAllCameras = false
            scanner.startScanning()
        }
    }
    
    func stopScanning() {
        if isScanning {
            scanner.stopScanning()
            isScanning = false
            print("Scan stopped. Found \(cameras.count) cameras")
        }
    }
    
    // Start periodic scanning
    func startPeriodicScanning(interval: TimeInterval = 60.0) {
        guard isBluetoothReady else {
            print("Bluetooth not ready, will start scanning when ready")
            return
        }
        
        scanner.startPeriodicScanning(interval: interval)
        isScanning = true
    }
    
    // Stop periodic scanning
    func stopPeriodicScanning() {
        scanner.stopPeriodicScanning()
        isScanning = false
    }
    
    // MARK: - ScannerDelegate methods
    func scannerDidUpdateCameras(_ cameras: [Camera]) {
        self.cameraDict = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        objectWillChange.send()
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
            isPoweringOn = false
        case .poweredOff:
            print("Bluetooth is powered off")
            bluetoothState = "Powered Off"
            isBluetoothReady = false
            DispatchQueue.main.async {
                self.stopPeriodicScanning()
                self.cameraDict.removeAll()
                self.isPoweringOn = false
            }
        case .resetting:
            print("Bluetooth is resetting")
            bluetoothState = "Resetting"
            isBluetoothReady = false
            isPoweringOn = true
        case .unauthorized:
            print("Bluetooth is unauthorized")
            bluetoothState = "Unauthorized"
            isBluetoothReady = false
            isPoweringOn = false
        case .unsupported:
            print("Bluetooth is unsupported")
            bluetoothState = "Unsupported"
            isPoweringOn = false
            isBluetoothReady = false
        case .unknown:
            print("Bluetooth state is unknown")
            bluetoothState = "Unknown"
            isBluetoothReady = false
        @unknown default:
            print("Unknown Bluetooth state")
            isPoweringOn = false
            bluetoothState = "Unknown State"
            isBluetoothReady = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        scanner.handleDiscoveredPeripheral(peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
}
