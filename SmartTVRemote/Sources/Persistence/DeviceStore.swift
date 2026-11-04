import Foundation

/// Persistencia de los televisores guardados (UserDefaults). Los secretos NO se guardan aquí, sino en el Keychain.
@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [TVDevice] = []
    @Published private(set) var selectedID: String?

    private let devicesKey = "devices.v1"
    private let selectedKey = "devices.selected.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: devicesKey),
           let decoded = try? JSONDecoder().decode([TVDevice].self, from: data) {
            devices = decoded
        }
        selectedID = UserDefaults.standard.string(forKey: selectedKey)
        if selectedDevice == nil { selectedID = devices.first?.id }
    }

    var selectedDevice: TVDevice? { devices.first { $0.id == selectedID } }

    func device(id: String) -> TVDevice? { devices.first { $0.id == id } }

    func upsert(_ device: TVDevice, select: Bool = false) {
        if let i = devices.firstIndex(where: { $0.id == device.id }) {
            // Conserva datos del usuario (nombre editado, MAC) y actualiza la red.
            var merged = devices[i]
            merged.host = device.host
            merged.port = device.port
            if merged.serviceName == nil { merged.serviceName = device.serviceName }
            devices[i] = merged
        } else {
            devices.append(device)
        }
        if select { selectedID = device.id }
        persist()
    }

    func select(_ id: String?) { selectedID = id; persist() }

    func update(_ id: String, _ change: (inout TVDevice) -> Void) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        change(&devices[i])
        persist()
    }

    func remove(_ id: String) {
        KeychainStore.removePairing(deviceID: id)
        devices.removeAll { $0.id == id }
        if selectedID == id { selectedID = devices.first?.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: devicesKey) }
        UserDefaults.standard.set(selectedID, forKey: selectedKey)
    }
}
