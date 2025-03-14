//
//  BluetoothScanner.swift
//  CameraStatus
//
//  Created by fra on 14/03/2025.
//

import Foundation
import CoreBluetooth

// Protocol for scanner to communicate with BLEManager
protocol ScannerDelegate: AnyObject {
    func scannerDidUpdateCameras(_ cameras: [Camera])
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
        
        // For debugging - log all discovered devices with their names
        if let name = peripheral.name {
            print("Discovered device: \(name) (UUID: \(peripheralId), RSSI: \(rssi.intValue))")
        }
        
        // Loop through camera identifiers to see if any can identify this peripheral
        for identifier in cameraIdentifiers {
            if identifier.canIdentifyCamera(peripheral: peripheral, advertisementData: advertisementData) {
                if let camera = identifier.createCamera(peripheral: peripheral, rssi: rssi) {
                    // Use the dictionary to ensure uniqueness
                    cameraDict[peripheralId] = camera
                    print("Found camera: \(camera.name) (UUID: \(peripheralId), RSSI: \(rssi.intValue))")
                    break
                }
            }
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
