import Foundation

/// Sesión del protocolo Android TV Remote v2 sobre un canal TLS (puerto 6466).
///
/// Se encarga del handshake (configure → set_active → start), de responder a los ping del televisor
/// y de traducir los mensajes entrantes a `Event`.
final class RemoteSession {
    enum Event {
        case ready
        case power(Bool)
        case volume(VolumeInfo)
        case app(String)
        case ime(ImeFieldState)
        case closed(TVError)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let channel: TLSChannel
    private let host: String
    private var readTask: Task<Void, Never>?
    private var readySent = false
    private let lock = NSLock()
    private var _lastReceived = Date()
    private var _imeField: ImeFieldState?

    var lastReceived: Date { lock.lock(); defer { lock.unlock() }; return _lastReceived }
    var imeField: ImeFieldState? { lock.lock(); defer { lock.unlock() }; return _imeField }
    var serverCertificate: ServerCertificate? { channel.serverCertificate }

    init(device: TVDevice, identity: SecIdentity, pinnedFingerprint: Data?) {
        host = device.host
        channel = TLSChannel(host: device.host, port: device.port, identity: identity, pinnedFingerprint: pinnedFingerprint)
        var cont: AsyncStream<Event>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        continuation = cont
    }

    func connect() async throws {
        try await channel.open()
        readTask = Task { [weak self] in await self?.readLoop() }
    }

    func close() {
        readTask?.cancel()
        channel.close()
        continuation.finish()
    }

    // MARK: Envío

    func sendKey(_ key: AndroidKey, direction: KeyDirection = .short) {
        channel.send(RemoteProtocol.key(key, direction: direction))
    }

    func launch(link: String) { channel.send(RemoteProtocol.appLink(link)) }

    /// Reemplaza el texto del campo enfocado del televisor. Devuelve `false` si no hay campo activo.
    @discardableResult
    func sendText(_ text: String) -> Bool {
        guard let field = imeField else { return false }
        channel.send(RemoteProtocol.text(text, field: field))
        return true
    }

    // MARK: Recepción

    private func readLoop() async {
        do {
            while !Task.isCancelled {
                let data = try await channel.receiveMessage()
                touch()
                try handle(RemoteProtocol.parse(data))
            }
        } catch {
            if !Task.isCancelled { continuation.yield(.closed(TVError.from(error, host: host))) }
        }
        continuation.finish()
    }

    private func touch() {
        lock.lock(); defer { lock.unlock() }
        _lastReceived = Date()
    }

    private func store(_ field: ImeFieldState) {
        lock.lock(); defer { lock.unlock() }
        _imeField = field
    }

    private func markReady() {
        guard !readySent else { return }
        readySent = true
        continuation.yield(.ready)
    }

    private func handle(_ event: RemoteEvent) throws {
        switch event {
        case .configure:
            channel.send(RemoteProtocol.configure(model: "iPhone", vendor: "Apple",
                                                  package: "com.ivansosa.smarttvremote", version: "1.0.0"))
        case .setActive:
            channel.send(RemoteProtocol.setActive())
            markReady()
        case .start(let started):
            continuation.yield(.power(started))
            markReady()
        case .ping(let value):
            channel.send(RemoteProtocol.pingResponse(value))
        case .volume(let info):
            continuation.yield(.volume(info))
        case .ime(let app, let field):
            if let app, !app.isEmpty { continuation.yield(.app(app)) }
            if let field {
                store(field)
                continuation.yield(.ime(field))
            }
        case .imeShow(let field):
            if let field {
                let merged = ImeFieldState(imeCounter: imeField?.imeCounter ?? 0, fieldCounter: field.fieldCounter, value: field.value)
                store(merged)
                continuation.yield(.ime(merged))
            }
        case .error, .other:
            break
        }
    }
}
