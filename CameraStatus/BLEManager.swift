import Foundation
import CoreBluetooth

class BLEManager: NSObject, ObservableObject, ScannerDelegate {
    // Camera storage
    @Published private var cameraDict: [String: Camera] = [:]
    var cameras: [Camera] {
        Array(cameraDict.values)
    }
    
    // Status properties
    @Published var isScanning = false
    @Published var bluetoothState: String = "Unknown"
    @Published var isBluetoothReady = false
    @Published var isPoweringOn = false
    @Published var powerOnStatus: String = ""
    
    // Core BLE components
    private var centralManager: CBCentralManager!
    private var scanner: BluetoothScanner!
    
    // Camera controllers
    private var cameraControllers: [CameraController] = []
    private var activeController: CameraController?
    
    override init() {
        super.init()
        // Initialize BLE central manager
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // Initialize scanner with this manager as delegate
        scanner = BluetoothScanner(centralManager: centralManager)
        scanner.delegate = self
        
        // Register camera identifiers
        scanner.registerCameraIdentifier(EM5CameraIdentifier())
        scanner.registerCameraIdentifier(RicohCameraIdentifier())
        
        // Initialize camera controllers
        cameraControllers.append(EM5CameraController())
        
        print("BLEManager initialized")
    }
    
    func startScanning() {
        if isBluetoothReady {
            isScanning = true
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
    
    // Power on a specific camera using the appropriate controller
    func powerOnCamera(camera: Camera) {
        // Don't allow multiple power-on attempts
        guard !isPoweringOn else {
            print("Already in the process of powering on a camera")
            return
        }
        
        // Find a controller that can power on this camera
        if let controller = cameraControllers.first(where: { $0.canPowerOn(camera: camera) }) {
            isPoweringOn = true
            powerOnStatus = "Preparing to connect..."
            activeController = controller
            
            // Start the power-on process
            controller.powerOn(camera: camera, centralManager: centralManager) { [weak self] (completed, status) in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    // Update status
                    self.powerOnStatus = status
                    
                    // If the operation is complete (success or failure), reset state
                    if completed {
                        // Delay resetting isPoweringOn to allow the user to read the message
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            self.isPoweringOn = false
                            self.activeController = nil
                        }
                    }
                }
            }
        } else {
            print("No controller available for camera: \(camera.name)")
            powerOnStatus = "This camera doesn't support power-on"
            
            // Reset status after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.powerOnStatus = ""
            }
        }
    }
    
    // MARK: - ScannerDelegate methods
    func scannerDidUpdateCameras(_ cameras: [Camera]) {
        self.cameraDict = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        objectWillChange.send()
    }
    
    func scannerDidStopScanning() {
        DispatchQueue.main.async {
            self.isScanning = false
        }
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
        // If we're in the process of powering on a camera, delegate to the active controller
        if isPoweringOn, let controller = activeController as? EM5CameraController {
            controller.didFindPeripheral(peripheral, advertisementData: advertisementData, rssi: RSSI)
        } else {
            // Otherwise, delegate to the scanner for normal device discovery
            scanner.handleDiscoveredPeripheral(peripheral, advertisementData: advertisementData, rssi: RSSI)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let controller = activeController as? EM5CameraController {
            controller.didConnect(peripheral: peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let controller = activeController as? EM5CameraController {
            controller.didFailToConnect(peripheral: peripheral, error: error)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let controller = activeController as? EM5CameraController {
            controller.didDisconnect(peripheral: peripheral, error: error)
        }
    }
}
