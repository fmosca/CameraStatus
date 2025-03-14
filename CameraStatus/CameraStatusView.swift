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
                HStack {
                    ProgressView()
                    Text("Scanning for cameras...")
                }
                .padding(.vertical, 5)
            } else if bleManager.cameras.isEmpty {
                Text("No cameras detected")
                    .foregroundColor(.secondary)
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
        .frame(width: 300)
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
struct Camera: Identifiable, Hashable {
    let id: String // Immutable UUID string
    let name: String
    let isAvailable: Bool
    let rssi: Int
    let lastSeen: Date
    
    // Hashable implementation
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Camera, rhs: Camera) -> Bool {
        return lhs.id == rhs.id
    }
}
