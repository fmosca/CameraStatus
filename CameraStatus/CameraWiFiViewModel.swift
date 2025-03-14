import Foundation
import Combine

class CameraWiFiViewModel: ObservableObject {
    @Published var camerasWithWiFiStatus: [(camera: Camera, wifiAvailable: Bool)] = []
    @Published var connectedNetwork: String?
    
    private var bleManager: BLEManager
    private var wifiMonitor: WiFiMonitor
    private var cancellables = Set<AnyCancellable>()
    
    init(bleManager: BLEManager) {
        self.bleManager = bleManager
        self.wifiMonitor = WiFiMonitor()
        
        // Subscribe to camera updates from BLEManager
        bleManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateCameraWiFiStatus(cameras: self.bleManager.cameras)
            }
            .store(in: &cancellables)
        
        // Subscribe to WiFi SSID updates
        wifiMonitor.$connectedSSID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ssid in
                self?.connectedNetwork = ssid
                self?.updateCameraWiFiStatus(cameras: bleManager.cameras)
            }
            .store(in: &cancellables)
        
        // Start monitoring WiFi
        wifiMonitor.startMonitoring()
    }
    
    private func updateCameraWiFiStatus(cameras: [Camera]) {
        camerasWithWiFiStatus = cameras.map { camera in
            // Extract the camera identifier to match with WiFi
            let identifier = self.extractIdentifier(from: camera.name)
            let wifiAvailable = wifiMonitor.isConnectedTo(networkContaining: identifier)
            
            return (camera: camera, wifiAvailable: wifiAvailable)
        }
    }
    
    private func extractIdentifier(from cameraName: String) -> String {
        // Extract identifiers like "BJ8A15412" from camera names
        if cameraName.contains("BJ8A15412") {
            return "BJ8A15412"
        } else if cameraName.contains("E-M5MKIII") {
            return "E-M5MKIII"
        } else if cameraName.contains("GR_5A9E88") {
            return "GR_5A9E88"
        }
        
        // Return the whole name as fallback
        return cameraName
    }
    
    deinit {
        wifiMonitor.stopMonitoring()
    }
}