import SwiftUI

/// Contenedor de dependencias de la app.
@MainActor
final class AppContainer: ObservableObject {
    let settings = AppSettings()
    let store = DeviceStore()
    let connection: TVConnectionManager
    let viewModel: RemoteViewModel

    init() {
        let connection = TVConnectionManager(store: store, settings: settings)
        self.connection = connection
        viewModel = RemoteViewModel(connection: connection, feedback: Feedback(settings: settings))
    }
}

@main
struct SmartTVRemoteApp: App {
    @StateObject private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RemoteView(viewModel: container.viewModel)
                .environmentObject(container.connection)
                .environmentObject(container.settings)
                .preferredColorScheme(container.settings.theme.colorScheme)
                .task { container.connection.connect() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: container.connection.sceneDidBecomeActive()
            case .background: container.connection.sceneDidEnterBackground()
            default: break
            }
        }
    }
}
