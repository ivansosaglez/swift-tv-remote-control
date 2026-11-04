import Foundation

/// Aplicaciones con acceso directo en el mando.
enum StreamingApp: String, CaseIterable, Identifiable {
    case netflix, prime, max, youtube, twitch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .netflix: return "Netflix"
        case .prime: return "Prime Video"
        case .max: return "Max"
        case .youtube: return "YouTube"
        case .twitch: return "Twitch"
        }
    }

    /// Enlaces (deep links) que el televisor resuelve hacia la app instalada. Se prueban en orden.
    var links: [String] {
        switch self {
        case .netflix: return ["https://www.netflix.com/title", "netflix://"]
        case .prime: return ["https://app.primevideo.com", "https://www.primevideo.com"]
        case .max: return ["https://play.max.com", "https://play.hbomax.com"]
        case .youtube: return ["https://www.youtube.com"]
        case .twitch: return ["https://www.twitch.tv", "twitch://"]
        }
    }

    /// Paquetes Android conocidos, para confirmar qué app queda en primer plano.
    var packages: [String] {
        switch self {
        case .netflix: return ["com.netflix.ninja"]
        case .prime: return ["com.amazon.amazonvideo.livingroom", "com.amazon.avod.thirdpartyclient"]
        case .max: return ["com.wbd.stream", "com.hbo.hbonow", "com.hbo.hbomax"]
        case .youtube: return ["com.google.android.youtube.tv", "com.google.android.youtube.tvunplugged"]
        case .twitch: return ["tv.twitch.android.app", "tv.twitch.android.viewer"]
        }
    }
}

enum LaunchOutcome: Equatable {
    case opened
    /// Orden enviada pero la TV no informa de la app en primer plano: no se puede confirmar.
    case sentUnconfirmed
    case likelyNotInstalled
    case notConnected
}

/// Lanza aplicaciones en el televisor mediante enlaces de app del protocolo remoto.
///
/// El protocolo no ofrece la lista de apps instaladas. Para detectar que una app no está
/// instalada se observa qué paquete pasa a primer plano tras enviar el enlace.
@MainActor
final class AppLauncher {
    private unowned let connection: TVConnectionManager

    init(connection: TVConnectionManager) { self.connection = connection }

    func launch(_ app: StreamingApp) async -> LaunchOutcome {
        guard connection.state.isConnected else { return .notConnected }
        if let current = connection.currentApp, app.packages.contains(current) { return .opened }

        for link in app.links {
            connection.sendAppLink(link)
            for _ in 0..<12 { // hasta ~3 s por enlace
                try? await Task.sleep(nanoseconds: 250_000_000)
                if let current = connection.currentApp, app.packages.contains(current) { return .opened }
            }
            if !connection.reportsCurrentApp { return .sentUnconfirmed }
        }
        return connection.reportsCurrentApp ? .likelyNotInstalled : .sentUnconfirmed
    }
}
