import Foundation
import CoreBluetooth

// Protocol for scanner to communicate with BLEManager
protocol ScannerDelegate: AnyObject {
    func scannerDidUpdateCameras(_ cameras: [Camera])
    func scannerDidStopScanning()
}

class BluetoothScanner {
    private var centralManager: CBCentralManager
    private var scanTimer: Timer?
    private var timeoutTimer: Timer?
    private var cameraIdentifiers: [CameraIdentifier] = []
    
    // Dictionary to store discovered cameras
    private var cameraDict: [String: Camera] = [:] {
        didSet {
            notifyDelegate()
        }
    }
    
    // Allow external registration of camera identifiers
    weak var delegate: ScannerDelegate?
    
    init(centralManager: CBCentralManager) {
        self.centralManager = centralManager
    }
    
    func registerCameraIdentifier(_ identifier: CameraIdentifier) {
        cameraIdentifiers.append(identifier)
    }
    
    private func notifyDelegate() {
        let cameras = Array(cameraDict.values)
        delegate?.scannerDidUpdateCameras(cameras)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth not available: \(centralManager.state.rawValue)")
            return
        }
        
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
        centralManager.stopScan()
        timeoutTimer?.invalidate()
        print("Scanner stopped scanning")
        delegate?.scannerDidStopScanning()
    }
    
    // Start periodic scanning
    func startPeriodicScanning(interval: TimeInterval = 60.0) {
        // Invalidate any existing timer
        scanTimer?.invalidate()
        
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
    
    // Process discovered peripherals
    func handleDiscoveredPeripheral(_ peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        let peripheralId = peripheral.identifier.uuidString
        
        // Early check if this might be a camera to reduce noise
        var mightBeCamera = false
        if let name = peripheral.name {
            // Check if the name contains "BJ8A", "EM5", "GR_", "Camera", etc.
            mightBeCamera = name.contains("BJ8A") ||
                           name.contains("E-M5") ||
                           name.contains("GR_") ||
                           name.contains("Camera") ||
                           name.contains("Olympus") ||
                           name.contains("Ricoh")
        }
        
        // Loop through camera identifiers to see if any can identify this peripheral
        for identifier in cameraIdentifiers {
            if identifier.canIdentifyCamera(peripheral: peripheral, advertisementData: advertisementData) {
                if let camera = identifier.createCamera(peripheral: peripheral, rssi: rssi) {
                    // Only log when we actually find a camera
                    print("Found camera: \(camera.name) (UUID: \(peripheralId), RSSI: \(rssi.intValue))")
                    
                    // Use the dictionary to ensure uniqueness
                    cameraDict[peripheralId] = camera
                    break
                }
                
                // If identified as a camera but couldn't create it, still flag as camera
                mightBeCamera = true
            }
        }
        
        // Only log devices that might be cameras
        if mightBeCamera, let name = peripheral.name {
            print("Possible camera device: \(name) (UUID: \(peripheralId), RSSI: \(rssi.intValue))")
        }
        
        // If we have at least 2 cameras, stop scanning
        if cameraDict.count >= 2 {
            print("Multiple cameras found, stopping scan")
            stopScanning()
        }
    }
    deinit {
        stopPeriodicScanning()
    }
}
