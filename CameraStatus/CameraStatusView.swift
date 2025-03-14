import SwiftUI

struct CameraStatusView: View {
    @StateObject private var bleManager = BLEManager()
    
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
            } else if bleManager.cameras.isEmpty {
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
                        Text("Found \(bleManager.cameras.count) cameras")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(Array(bleManager.cameras), id: \.id) { camera in
                            HStack {
                                Image(systemName: "camera")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(camera.name)
                                        .fontWeight(.medium)
                                    Text("Signal: \(camera.rssi) dBm • Last updated: \(timeAgo(date: camera.lastSeen))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
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
        .frame(width: 320)  // Slightly wider to accommodate the new text
        .onAppear {
            // Schedule a delay before starting periodic scanning
            // This allows the view to fully appear before potentially showing permissions
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
