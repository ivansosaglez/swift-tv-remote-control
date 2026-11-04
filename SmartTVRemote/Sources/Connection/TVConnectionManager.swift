import Foundation
import SwiftUI

/// Qué puede hacer el botón de encendido en este momento.
enum PowerCapability: Equatable {
    /// Conectado: se envía la tecla POWER por el protocolo remoto.
    case available
    /// Desconectado pero con MAC guardada: se intenta Wake‑on‑LAN.
    case wakeOnLAN
    /// Desconectado y sin MAC: depende de que el televisor acepte conexiones en reposo.
    case unavailable
}

/// Orquesta la conexión con el televisor activo: conexión, reconexión, estado y envío de comandos.
@MainActor
final class TVConnectionManager: ObservableObject {
    // Estado publicado
    @Published private(set) var state: ConnectionState = .noDevice
    @Published private(set) var device: TVDevice?
    @Published private(set) var volume: VolumeInfo?
    @Published private(set) var currentApp: String?
    @Published private(set) var reportsCurrentApp = false
    @Published private(set) var tvPoweredOn: Bool?
    @Published private(set) var imeField: ImeFieldState?
    /// Mensaje breve y no intrusivo para la interfaz.
    @Published var notice: String?

    let store: DeviceStore
    let settings: AppSettings

    private var session: RemoteSession?
    private var runTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var attempt = 0
    private var intentionalDisconnect = false
    private var userDisconnected = false
    private var expectingStandby = false
    private var wakeDeadline: Date?
    private let refreshDiscovery = DeviceDiscovery()
    private let maxAttempts = 6
    private let backoff: [Double] = [0.4, 1, 2, 4, 8, 15]

    init(store: DeviceStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        device = store.selectedDevice
        state = device == nil ? .noDevice : .disconnected
    }

    // MARK: - Capacidades

    var powerCapability: PowerCapability {
        if state.isConnected { return .available }
        if let mac = device?.macAddress, WakeOnLAN.normalizedMAC(mac) != nil { return .wakeOnLAN }
        return .unavailable
    }

    // MARK: - Conexión

    /// Conecta con el televisor seleccionado (o lo reintenta).
    func connect(resetAttempts: Bool = true) {
        guard let device = store.selectedDevice else {
            self.device = nil
            state = .noDevice
            return
        }
        self.device = device
        cancelWork()
        if resetAttempts { attempt = 0 }
        intentionalDisconnect = false
        userDisconnected = false
        expectingStandby = false

        guard device.isPaired else {
            state = .pairingRequired
            return
        }
        state = attempt == 0 ? .connecting : .reconnecting(attempt: attempt)
        runTask = Task { await run(device) }
    }

    func select(_ device: TVDevice) {
        store.upsert(device, select: true)
        disconnectQuietly()
        connect()
    }

    /// Desconexión pedida por el usuario: no se reconecta sola.
    func disconnect() {
        disconnectQuietly()
        userDisconnected = true
        state = device == nil ? .noDevice : .disconnected
    }

    func forget(_ id: String) {
        let wasSelected = store.selectedID == id
        store.remove(id)
        if wasSelected {
            disconnectQuietly()
            device = store.selectedDevice
            state = device == nil ? .noDevice : .disconnected
            if device != nil { connect() }
        }
    }

    /// Refresca la copia local del televisor tras editar el almacén (nombre, MAC, IP).
    func refreshDevice() { device = store.selectedDevice }

    func pairingCompleted(_ device: TVDevice) {
        store.upsert(device, select: true)
        connect()
    }

    func sceneDidBecomeActive() {
        guard device != nil, !userDisconnected else { return }
        switch state {
        case .disconnected, .failed: connect()
        default: break
        }
    }

    func sceneDidEnterBackground() {
        // iOS suspende los sockets en segundo plano: se cierra limpiamente y se reconecta al volver.
        guard state.isConnected || state.isBusy else { return }
        disconnectQuietly()
        state = .disconnected
    }

    // MARK: - Bucle de conexión

    private func run(_ device: TVDevice) async {
        do {
            let identity = try CertificateManager.shared.identity()
            let pin = KeychainStore.pinnedFingerprint(deviceID: device.id)
            let session = RemoteSession(device: device, identity: identity, pinnedFingerprint: pin)
            self.session = session
            try await session.connect()
            startHandshakeTimeout(for: session)

            for await event in session.events {
                guard self.session === session else { return }
                handle(event)
            }
            // El flujo terminó sin evento de cierre: se considera caída.
            if self.session === session { handleDrop(.connectionClosed) }
        } catch {
            guard !Task.isCancelled else { return }
            handleDrop(TVError.from(error, host: device.host))
        }
    }

    private func handle(_ event: RemoteSession.Event) {
        switch event {
        case .ready:
            attempt = 0
            wakeDeadline = nil
            state = .connected
            if let id = device?.id { store.update(id) { $0.lastConnected = Date() } }
            startWatchdog()
        case .power(let on):
            tvPoweredOn = on
        case .volume(let info):
            volume = info
        case .app(let package):
            currentApp = package
            reportsCurrentApp = true
        case .ime(let field):
            imeField = field
        case .closed(let error):
            handleDrop(error)
        }
    }

    private func startHandshakeTimeout(for session: RemoteSession) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.session === session, self.state != .connected else { return }
            session.close()
            self.handleDrop(.connectionClosed)
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, let s = self.session, self.state.isConnected else { return }
                if Date().timeIntervalSince(s.lastReceived) > 30 {
                    s.close()
                    self.handleDrop(.timeout)
                    return
                }
            }
        }
    }

    /// Gestiona la pérdida o el fallo de la conexión, decidiendo si reintentar.
    private func handleDrop(_ error: TVError) {
        session?.close()
        session = nil
        watchdog?.cancel()
        volume = nil
        imeField = nil

        if intentionalDisconnect { state = .disconnected; return }

        if expectingStandby {
            expectingStandby = false
            tvPoweredOn = false
            state = .disconnected
            return
        }

        let waking = (wakeDeadline.map { Date() < $0 } ?? false)
        if settings.autoReconnect, error.isRetryable, attempt < maxAttempts || waking {
            attempt += 1
            state = .reconnecting(attempt: attempt)
            let delay = waking ? 3 : backoff[min(attempt - 1, backoff.count - 1)]
            retryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                await self.refreshHostIfNeeded()
                guard !Task.isCancelled else { return }
                self.connect(resetAttempts: false)
            }
        } else {
            attempt = 0
            state = .failed(error)
        }
    }

    /// Si el router ha cambiado la IP del televisor, la recupera por Bonjour.
    private func refreshHostIfNeeded() async {
        guard attempt >= 2, let device = store.selectedDevice, let name = device.serviceName else { return }
        if let ip = await refreshDiscovery.findHost(serviceName: name, timeout: 3), ip != device.host {
            store.update(device.id) { $0.host = ip }
        }
    }

    private func disconnectQuietly() {
        intentionalDisconnect = true
        cancelWork()
        session?.close()
        session = nil
        volume = nil
        imeField = nil
    }

    private func cancelWork() {
        runTask?.cancel(); runTask = nil
        retryTask?.cancel(); retryTask = nil
        watchdog?.cancel(); watchdog = nil
        session?.close(); session = nil
    }

    // MARK: - Comandos

    /// Envía una tecla. Devuelve `false` si no hay conexión.
    @discardableResult
    func send(_ key: AndroidKey, direction: KeyDirection = .short) -> Bool {
        guard state.isConnected, let session else { return false }
        session.sendKey(key, direction: direction)
        return true
    }

    func sendAppLink(_ link: String) { session?.launch(link: link) }

    /// Sustituye el texto del campo del televisor. `false` si no hay campo de texto enfocado.
    @discardableResult
    func sendText(_ text: String) -> Bool {
        guard state.isConnected, let session else { return false }
        return session.sendText(text)
    }

    var hasFocusedTextField: Bool { imeField != nil }

    /// Enciende o apaga. Devuelve un mensaje informativo para el usuario si procede.
    @discardableResult
    func togglePower() -> String? {
        switch powerCapability {
        case .available:
            // Si el televisor estaba encendido, se espera que cierre la conexión al entrar en reposo.
            expectingStandby = tvPoweredOn != false
            send(.power)
            return expectingStandby ? "Apagando el televisor…" : "Encendiendo el televisor…"
        case .wakeOnLAN:
            guard let device, let mac = device.macAddress else { return nil }
            _ = WakeOnLAN.send(mac: mac, targetHost: device.host)
            wakeDeadline = Date().addingTimeInterval(45)
            attempt = 0
            connect(resetAttempts: false)
            return "Enviando orden de encendido (Wake‑on‑LAN)…"
        case .unavailable:
            wakeDeadline = Date().addingTimeInterval(15)
            if device != nil { connect(resetAttempts: false) }
            return "El encendido remoto depende del modelo y de su configuración. Añade la dirección MAC del televisor en Ajustes para probar Wake‑on‑LAN."
        }
    }
}
