import SwiftUI

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var isError = false
}

/// Lógica de presentación del mando: pulsaciones, avisos y accesos directos.
@MainActor
final class RemoteViewModel: ObservableObject {
    let connection: TVConnectionManager
    let feedback: Feedback
    private(set) lazy var launcher = AppLauncher(connection: connection)

    @Published var toast: Toast?
    @Published var launchingApp: StreamingApp?
    private var toastTask: Task<Void, Never>?

    init(connection: TVConnectionManager, feedback: Feedback) {
        self.connection = connection
        self.feedback = feedback
    }

    var tvName: String { connection.device?.name ?? "Smart TV Remote" }
    var state: ConnectionState { connection.state }

    /// Pulsación de una tecla: háptica inmediata + envío al televisor.
    func press(_ key: AndroidKey, strong: Bool = false) {
        feedback.tap(strong: strong)
        if !connection.send(key) { feedback.error() }
    }

    func launch(_ app: StreamingApp) {
        feedback.tap(strong: true)
        guard connection.state.isConnected else {
            show("Conecta primero con tu televisor.", error: true)
            return
        }
        launchingApp = app
        Task {
            let outcome = await launcher.launch(app)
            launchingApp = nil
            switch outcome {
            case .opened: break
            case .sentUnconfirmed: show("Orden enviada a \(app.title). La TV no confirma si se abrió.")
            case .likelyNotInstalled: show("\(app.title) no parece estar instalada en este televisor.", error: true)
            case .notConnected: show("Sin conexión con el televisor.", error: true)
            }
        }
    }

    func togglePower() {
        feedback.tap(strong: true)
        if let message = connection.togglePower() { show(message) }
    }

    func show(_ text: String, error: Bool = false) {
        toast = Toast(text: text, isError: error)
        let current = toast?.id
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if !Task.isCancelled, toast?.id == current { withAnimation { toast = nil } }
        }
    }
}
