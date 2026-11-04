import Foundation
import Network

/// Errores de la app con mensajes claros en español y sugerencia de recuperación.
enum TVError: LocalizedError, Equatable {
    case localNetworkDenied
    case timeout
    case unreachable(String)
    case connectionRefused
    case connectionClosed
    case certificateMismatch
    case identityUnavailable(String)
    case pairingRejected
    case wrongCode
    case pairingNotAvailable
    case notConnected
    case invalidAddress
    case noAndroidTVAtAddress
    case protocolError(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .localNetworkDenied:
            return "iOS ha bloqueado el acceso a la red local."
        case .timeout:
            return "El televisor no responde."
        case .unreachable(let host):
            return "No se puede llegar a \(host). ¿Está encendido y en la misma Wi‑Fi?"
        case .connectionRefused:
            return "El televisor ha rechazado la conexión."
        case .connectionClosed:
            return "El televisor ha cerrado la conexión."
        case .certificateMismatch:
            return "La identidad del televisor ha cambiado desde el emparejamiento."
        case .identityUnavailable(let reason):
            return "No se pudo preparar la identidad segura de la app (\(reason))."
        case .pairingRejected:
            return "El televisor ha rechazado el emparejamiento."
        case .wrongCode:
            return "El código introducido no es correcto."
        case .pairingNotAvailable:
            return "El televisor no ofrece un emparejamiento compatible."
        case .notConnected:
            return "No hay conexión con el televisor."
        case .invalidAddress:
            return "La dirección IP no es válida."
        case .noAndroidTVAtAddress:
            return "No se encontró el servicio de mando Android TV en esa dirección."
        case .protocolError(let detail):
            return "Respuesta inesperada del televisor (\(detail))."
        case .network(let detail):
            return "Error de red: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .localNetworkDenied:
            return "Activa «Red local» para Smart TV Remote en Ajustes ▸ Privacidad y seguridad ▸ Red local."
        case .timeout, .unreachable, .connectionClosed:
            return "Comprueba que el televisor está encendido y que iPhone y TV usan la misma red Wi‑Fi."
        case .connectionRefused:
            return "Algunos televisores solo aceptan conexiones con la pantalla encendida. Enciéndelo e inténtalo de nuevo."
        case .certificateMismatch, .pairingRejected:
            return "Vuelve a emparejar el televisor desde Ajustes."
        case .wrongCode:
            return "Escribe el código tal y como aparece en la pantalla del televisor."
        case .noAndroidTVAtAddress:
            return "Revisa la IP en los ajustes de red del televisor y que «Control remoto» esté habilitado."
        default:
            return nil
        }
    }

    /// `true` si tiene sentido reintentar la conexión automáticamente.
    var isRetryable: Bool {
        switch self {
        case .timeout, .unreachable, .connectionClosed, .connectionRefused, .network, .notConnected: return true
        default: return false
        }
    }

    /// Traduce errores de Network.framework a `TVError`.
    static func from(_ error: Error, host: String = "el televisor") -> TVError {
        if let tv = error as? TVError { return tv }
        if let nw = error as? NWError {
            switch nw {
            case .posix(let code):
                switch code {
                case .ECONNREFUSED: return .connectionRefused
                case .ETIMEDOUT: return .timeout
                case .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ENETDOWN: return .unreachable(host)
                case .ECONNRESET, .EPIPE, .ENOTCONN: return .connectionClosed
                default: return .network(nw.localizedDescription)
                }
            case .dns(let code):
                // kDNSServiceErr_PolicyDenied (-65570): permiso de Red local denegado.
                if code == -65570 { return .localNetworkDenied }
                return .network(nw.localizedDescription)
            case .tls:
                return .connectionClosed
            default:
                return .network(nw.localizedDescription)
            }
        }
        return .network(error.localizedDescription)
    }
}
