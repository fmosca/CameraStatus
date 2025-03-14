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
