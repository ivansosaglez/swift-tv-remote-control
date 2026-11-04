import Foundation

/// Estado de la conexión con el televisor activo.
enum ConnectionState: Equatable {
    /// No hay ningún televisor configurado.
    case noDevice
    case disconnected
    case connecting
    /// Reintentando tras una pérdida de conexión (intento n).
    case reconnecting(attempt: Int)
    /// El televisor aún no ha sido emparejado con este iPhone.
    case pairingRequired
    case connected
    case failed(TVError)

    var isConnected: Bool { self == .connected }

    var isBusy: Bool {
        switch self {
        case .connecting, .reconnecting: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .noDevice: return "Sin televisor"
        case .disconnected: return "Desconectado"
        case .connecting: return "Conectando…"
        case .reconnecting(let n): return "Reconectando (\(n))…"
        case .pairingRequired: return "Emparejamiento necesario"
        case .connected: return "Conectado"
        case .failed: return "Sin conexión"
        }
    }
}
