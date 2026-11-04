import Foundation

/// Televisor Android TV / Google TV guardado por el usuario.
struct TVDevice: Identifiable, Codable, Equatable, Hashable {
    /// Identificador estable: `mdns:<nombre del servicio>` o `ip:<dirección>` para altas manuales.
    var id: String
    /// Nombre mostrado (editable por el usuario).
    var name: String
    var host: String
    var port: UInt16 = RemoteProtocol.port
    /// Nombre original del servicio Bonjour, para reubicar el televisor si cambia su IP.
    var serviceName: String?
    /// MAC de la interfaz Wi‑Fi/Ethernet del televisor (opcional, solo para Wake‑on‑LAN).
    var macAddress: String?
    var lastConnected: Date?

    /// Un televisor está emparejado si existe su anclaje de confianza en el Keychain.
    var isPaired: Bool { KeychainStore.pinnedFingerprint(deviceID: id) != nil }
}

/// Televisor encontrado por Bonjour, aún no necesariamente guardado.
struct DiscoveredTV: Identifiable, Equatable {
    var id: String { "mdns:\(serviceName)" }
    let serviceName: String
    let host: String
    let port: UInt16

    var asDevice: TVDevice {
        TVDevice(id: id, name: serviceName, host: host, port: port, serviceName: serviceName)
    }
}
