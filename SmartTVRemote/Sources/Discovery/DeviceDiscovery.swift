import Foundation
import Network

/// Descubrimiento de Android TV / Google TV mediante Bonjour (`_androidtvremote2._tcp`).
@MainActor
final class DeviceDiscovery: ObservableObject {
    static let serviceType = "_androidtvremote2._tcp"

    @Published private(set) var results: [DiscoveredTV] = []
    @Published private(set) var isSearching = false
    @Published private(set) var error: TVError?

    private var browser: NWBrowser?
    private var resolving: [String: NWConnection] = [:]
    private var stopTask: Task<Void, Never>?

    /// Inicia la búsqueda. Se detiene sola tras `duration` segundos.
    func start(duration: TimeInterval = 20) {
        stop()
        error = nil
        results = []
        isSearching = true

        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .failed(let e), .waiting(let e):
                    self.error = TVError.from(e)
                    if case .failed = state { self.isSearching = false }
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] found, _ in
            Task { @MainActor in self?.handle(found) }
        }
        browser.start(queue: .main)
        self.browser = browser

        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled { self?.stop() }
        }
    }

    func stop() {
        stopTask?.cancel()
        browser?.cancel(); browser = nil
        resolving.values.forEach { $0.cancel() }
        resolving.removeAll()
        isSearching = false
    }

    private func handle(_ found: Set<NWBrowser.Result>) {
        let names = Set(found.compactMap { r -> String? in
            if case let .service(name, _, _, _) = r.endpoint { return name }
            return nil
        })
        results.removeAll { !names.contains($0.serviceName) }
        for result in found {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            if results.contains(where: { $0.serviceName == name }) || resolving[name] != nil { continue }
            resolve(name: name, endpoint: result.endpoint)
        }
    }

    /// Resuelve la IP abriendo (y cerrando enseguida) una conexión TCP al servicio Bonjour.
    private func resolve(name: String, endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let conn = NWConnection(to: endpoint, using: params)
        resolving[name] = conn
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let conn else { return }
            if case .ready = state, case let .hostPort(host, port)? = conn.currentPath?.remoteEndpoint {
                let hostString = Self.cleanHost(host)
                conn.cancel()
                Task { @MainActor in
                    guard let self else { return }
                    self.resolving[name] = nil
                    if !self.results.contains(where: { $0.serviceName == name }) {
                        self.results.append(DiscoveredTV(serviceName: name, host: hostString, port: port.rawValue))
                        self.results.sort { $0.serviceName < $1.serviceName }
                    }
                }
            } else if case .failed = state {
                conn.cancel()
                Task { @MainActor in self?.resolving[name] = nil }
            }
        }
        conn.start(queue: .main)
    }

    nonisolated static func cleanHost(_ host: NWEndpoint.Host) -> String {
        let s = "\(host)"
        return s.split(separator: "%").first.map(String.init) ?? s
    }

    /// Busca un servicio por nombre y devuelve su IP actual (útil si el router cambió la IP del televisor).
    func findHost(serviceName: String, timeout: TimeInterval = 4) async -> String? {
        start(duration: timeout + 1)
        defer { stop() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let hit = results.first(where: { $0.serviceName == serviceName }) { return hit.host }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    // MARK: Alta manual

    /// Comprueba que hay algo escuchando en el puerto del mando remoto de esa IP.
    nonisolated static func probe(host: String, port: UInt16 = RemoteProtocol.port, timeout: TimeInterval = 4) async -> Bool {
        await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            let lock = NSLock()
            var done = false
            let finish: (Bool) -> Void = { ok in
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                conn.cancel()
                cont.resume(returning: ok)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting: finish(false)
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    nonisolated static func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { p in
            p.count <= 3 && !p.isEmpty && p.allSatisfy(\.isNumber) && (Int(p) ?? 256) <= 255
        }
    }
}
