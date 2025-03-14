//
//  CameraIdentifier.swift
//  CameraStatus
//
//  Created by fra on 14/03/2025.
//

import Foundation
import CoreBluetooth

// Protocol for camera identification
protocol CameraIdentifier {
    func canIdentifyCamera(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool
    func createCamera(peripheral: CBPeripheral, rssi: NSNumber) -> Camera?
}

// MARK: - Olympus EM5 Camera Identifier

class EM5CameraIdentifier: CameraIdentifier {
    // The camera names to look for
    private let knownEM5CameraNames = [
        "BJ8A15412",         // EM5mkIII camera from Python script
        "E-M5MKIII-P-BJ8A15412" // Alternative name format
    ]
    
    private let serviceUUIDs: [CBUUID]? = nil // Add specific service UUIDs if known
    
    func canIdentifyCamera(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        // Check if the name matches known EM5 cameras
        if let name = peripheral.name {
            for cameraName in knownEM5CameraNames {
                if name.contains(cameraName) {
                    return true
                }
            }
        }
        
        // No match found
        return false
    }
    
    func createCamera(peripheral: CBPeripheral, rssi: NSNumber) -> Camera? {
        let peripheralId = peripheral.identifier.uuidString
        let name = peripheral.name ?? "EM5 Camera (\(peripheralId.suffix(6)))"
        
        // Create a Camera object with EM5 specific details if needed
        return Camera(
            id: peripheralId,
            name: name,
            isAvailable: true,
            rssi: rssi.intValue,
            lastSeen: Date()
        )
    }
}

// MARK: - Ricoh Camera Identifier

class RicohCameraIdentifier: CameraIdentifier {
    // Known names for Ricoh cameras
    private let knownNames = [
        "GR_5A9E88"  // Your existing camera
    ]
    
    // Known UUIDs for Ricoh cameras
    private let knownRicohUUIDs = [
        "10763D9D-22B1-A168-8B62-2CA083E3BE4F"  // GR_5A9E88 camera
    ]
    
    init() {
        // Default initialization with hardcoded known values
    }
    
    func canIdentifyCamera(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        let peripheralId = peripheral.identifier.uuidString
        
        // Check if UUID is in our known list
        if knownRicohUUIDs.contains(peripheralId) {
            return true
        }
        
        // Check name against known names
        if let name = peripheral.name {
            return knownNames.contains { name.contains($0) }
        }
        
        return false
    }
    
    func createCamera(peripheral: CBPeripheral, rssi: NSNumber) -> Camera? {
        let peripheralId = peripheral.identifier.uuidString
        let name = peripheral.name ?? "Ricoh Camera (\(peripheralId.suffix(6)))"
        
        return Camera(
            id: peripheralId,
            name: name,
            isAvailable: true,
            rssi: rssi.intValue,
            lastSeen: Date()
        )
    }
}
