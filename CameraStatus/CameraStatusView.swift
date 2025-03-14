import SwiftUI

struct CameraStatusView: View {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var viewModel: CameraWiFiViewModel
    
    init() {
        // Initialize the bleManager first
        let bleManager = BLEManager()
        // Then create the view model with the bleManager
        _bleManager = StateObject(wrappedValue: bleManager)
        _viewModel = StateObject(wrappedValue: CameraWiFiViewModel(bleManager: bleManager))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Camera Status")
                    .font(.headline)
                Spacer()
                Text("Bluetooth: \(bleManager.bluetoothState)")
                    .font(.caption)
                    .foregroundColor(bleManager.bluetoothState == "Powered On" ? .green : .red)
                Button(action: {
                    if bleManager.isBluetoothReady {
                        bleManager.startScanning()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(!bleManager.isBluetoothReady)
            }
            .padding(.bottom, 5)
            
            // WiFi status line
            if let connectedNetwork = viewModel.connectedNetwork {
                HStack {
                    Image(systemName: "wifi")
                        .foregroundColor(.green)
                    Text("Connected to: \(connectedNetwork)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 5)
            } else {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.gray)
                    Text("Not connected to WiFi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 5)
            }
            
            if !bleManager.isBluetoothReady {
                VStack(alignment: .center, spacing: 10) {
                    Text("Bluetooth Permission Required")
                        .font(.headline)
                    Text("This app needs Bluetooth permission to detect cameras.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("Request Permission") {
                        // This will trigger the permission prompt
                        bleManager.startPeriodicScanning()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            } else if bleManager.isScanning {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        ProgressView()
                        Text("Scanning for cameras...")
                    }
                    Text("This may take up to 25 seconds for cameras with long broadcast intervals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 5)
            } else if bleManager.isPoweringOn {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        ProgressView()
                        Text(bleManager.powerOnStatus)
                    }
                    Text("Communicating with the Olympus EM5 camera...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 5)
            } else if viewModel.camerasWithWiFiStatus.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No cameras detected")
                        .foregroundColor(.secondary)
                    Text("Try rescanning or verify your camera is in discoverable mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 5)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Found \(viewModel.camerasWithWiFiStatus.count) cameras")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(viewModel.camerasWithWiFiStatus, id: \.camera.id) { cameraWithWiFi in
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Image(systemName: "camera")
                                            .foregroundColor(.blue)
                                        Text(cameraWithWiFi.camera.name)
                                            .fontWeight(.medium)
                                    }
                                    Text("Signal: \(cameraWithWiFi.camera.rssi) dBm • Last updated: \(timeAgo(date: cameraWithWiFi.camera.lastSeen))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                
                                // WiFi status icon
                                Image(systemName: cameraWithWiFi.wifiAvailable ? "wifi" : "wifi.slash")
                                    .foregroundColor(cameraWithWiFi.wifiAvailable ? .green : .gray)
                                    .frame(width: 24, height: 24)
                                
                                // Power button for EM5 cameras
                                if cameraWithWiFi.camera.name.contains("BJ8A15412") || cameraWithWiFi.camera.name.contains("E-M5MKIII") {
                                    Button(action: {
                                        bleManager.powerOnCamera(camera: cameraWithWiFi.camera)
                                    }) {
                                        Image(systemName: "bolt.horizontal.circle")
                                            .foregroundColor(.blue)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .disabled(bleManager.isPoweringOn)
                                }
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(minHeight: 100, maxHeight: 300)
            }
        }
        .padding()
        .frame(width: 340)  // Wider to accommodate the WiFi status
        .onAppear {
            // Schedule a delay before starting periodic scanning
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if bleManager.isBluetoothReady {
                    bleManager.startPeriodicScanning()
                }
            }
        }
        .onDisappear {
            // Clean up when view disappears
            bleManager.stopPeriodicScanning()
        }
    }
    
    // Helper function to show relative time
    func timeAgo(date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}