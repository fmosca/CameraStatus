import Foundation
import NetworkExtension
import SystemConfiguration.CaptiveNetwork

class WiFiMonitor: ObservableObject {
    @Published private(set) var connectedSSID: String?
    
    private var timer: Timer?
    private let checkInterval: TimeInterval
    
    init(checkInterval: TimeInterval = 5.0) {
        self.checkInterval = checkInterval
        updateConnectedSSID()
    }
    
    func startMonitoring() {
        // Update immediately
        updateConnectedSSID()
        
        // Then start periodic updates
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.updateConnectedSSID()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateConnectedSSID() {
        // Use CNCopyCurrentNetworkInfo which works better for getting the current SSID
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else {
            print("Could not get network interfaces")
            connectedSSID = nil
            return
        }
        
        for interface in interfaces {
            if let networkInfo = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any],
               let ssid = networkInfo[kCNNetworkInfoKeySSID as String] as? String {
                print("Connected to WiFi: \(ssid)")
                connectedSSID = ssid
                return
            }
        }
        
        // No WiFi connection found
        print("No WiFi connection found")
        connectedSSID = nil
    }
    
    func isConnectedTo(networkContaining identifier: String) -> Bool {
        guard let ssid = connectedSSID else {
            return false
        }
        return ssid.contains(identifier)
    }
    
    deinit {
        stopMonitoring()
    }
}
