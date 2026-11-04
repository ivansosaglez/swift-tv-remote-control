import SwiftUI

/// Pantalla principal: mando a distancia.
struct RemoteView: View {
    @EnvironmentObject private var connection: TVConnectionManager
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: RemoteViewModel

    enum Sheet: Identifiable, Equatable {
        case settings, keyboard, pairing(TVDevice)
        var id: String {
            switch self {
            case .settings: return "settings"
            case .keyboard: return "keyboard"
            case .pairing(let d): return "pairing-\(d.id)"
            }
        }
    }

    @State private var sheet: Sheet?

    var body: some View {
        ZStack {
            AppBackground()
            if connection.state == .noDevice {
                onboarding
            } else {
                remote
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toast {
                ToastView(text: toast.text, isError: toast.isError)
                    .padding(.bottom, 24).padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.toast)
        .sheet(item: $sheet) { item in
            switch item {
            case .settings:
                SettingsView().environmentObject(connection).environmentObject(settings)
                    .preferredColorScheme(settings.theme.colorScheme)
            case .keyboard:
                KeyboardInputView(viewModel: viewModel, connection: connection)
                    .presentationDetents([.height(380), .large])
                    .preferredColorScheme(settings.theme.colorScheme)
            case .pairing(let device):
                PairingView(device: device)
                    .environmentObject(connection)
                    .preferredColorScheme(settings.theme.colorScheme)
            }
        }
        .onChange(of: connection.state) { _, newState in
            if newState == .pairingRequired, sheet == nil, let device = connection.device {
                sheet = .pairing(device)
            }
        }
        .onChange(of: connection.notice) { _, notice in
            if let notice { viewModel.show(notice); connection.notice = nil }
        }
    }

    // MARK: Mando

    private var remote: some View {
        VStack(spacing: 16) {
            topBar
            connectionBanner
            appShortcuts
            DPadView(viewModel: viewModel)
                .frame(maxWidth: 330)
                .padding(.horizontal, 6)
                .frame(maxHeight: .infinity)
            navigationRow
            bottomControls
                .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .opacity(connection.state.isConnected ? 1 : 0.75)
        .animation(.easeInOut(duration: 0.25), value: connection.state.isConnected)
    }

    private var topBar: some View {
        HStack {
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .frame(width: 46, height: 46)
                    .glassSurface(Circle())
            }
            .accessibilityLabel("Ajustes")

            Spacer(minLength: 8)

            Button { sheet = .settings } label: {
                VStack(spacing: 3) {
                    Text(viewModel.tvName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        ConnectionDot(state: connection.state)
                        Text(connection.state.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(viewModel.tvName), \(connection.state.label)")

            Spacer(minLength: 8)

            Button { viewModel.togglePower() } label: {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(connection.powerCapability == .unavailable ? Palette.secondaryText : Palette.danger)
                    .frame(width: 46, height: 46)
                    .glassSurface(Circle())
                    .opacity(connection.powerCapability == .unavailable ? 0.55 : 1)
            }
            .accessibilityLabel("Encender o apagar")
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch connection.state {
        case .failed(let error):
            banner(icon: "wifi.exclamationmark", text: error.errorDescription ?? "Sin conexión", tint: Palette.danger,
                   actionTitle: error == .certificateMismatch ? "Emparejar" : "Reconectar") {
                if error == .certificateMismatch, let d = connection.device { sheet = .pairing(d) } else { connection.connect() }
            }
        case .disconnected:
            banner(icon: "wifi.slash", text: "Conexión perdida", tint: Palette.connecting, actionTitle: "Reconectar") {
                connection.connect()
            }
        case .reconnecting(let n):
            banner(icon: "arrow.triangle.2.circlepath", text: "Reconectando… (intento \(n))", tint: Palette.connecting, actionTitle: nil) {}
        case .pairingRequired:
            banner(icon: "lock.shield", text: "Hay que emparejar este televisor", tint: Palette.connecting, actionTitle: "Emparejar") {
                if let d = connection.device { sheet = .pairing(d) }
            }
        default:
            EmptyView()
        }
    }

    private func banner(icon: String, text: String, tint: Color, actionTitle: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.primaryText).lineLimit(2)
            Spacer(minLength: 4)
            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle).font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(tint.opacity(0.9)))
                        .foregroundStyle(.black)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassSurface(Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var appShortcuts: some View {
        HStack {
            ForEach(StreamingApp.allCases) { app in
                PressableKey(action: { viewModel.launch(app) }) { pressed in
                    ZStack {
                        StreamingAppIcon(app: app)
                            .opacity(viewModel.launchingApp == app ? 0.25 : 1)
                        if viewModel.launchingApp == app { ProgressView().tint(Palette.primaryText) }
                    }
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.55)))
                    .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), pressed: pressed)
                }
                .accessibilityLabel("Abrir \(app.title)")
                if app != StreamingApp.allCases.last { Spacer(minLength: 4) }
            }
        }
    }

    private var navigationRow: some View {
        HStack(spacing: 14) {
            navKey("chevron.backward", "Atrás", .back)
            navKey("house.fill", "Inicio", .home)
            navKey("line.3.horizontal", "Menú", .menu)
        }
    }

    private func navKey(_ icon: String, _ label: String, _ key: AndroidKey) -> some View {
        PressableKey(action: { viewModel.press(key) }) { pressed in
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Palette.primaryText)
            .frame(maxWidth: .infinity).frame(height: 52)
            .glassSurface(Capsule(), pressed: pressed)
        }
        .accessibilityLabel(label)
    }

    private var bottomControls: some View {
        HStack(alignment: .center, spacing: 16) {
            VolumeView(viewModel: viewModel, connection: connection)
                .frame(height: 190)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    IconKey(systemName: "backward.fill", size: 52, accessibilityLabel: "Retroceder") { viewModel.press(.mediaRewind) }
                    IconKey(systemName: "playpause.fill", size: 52, tint: Palette.accent, accessibilityLabel: "Reproducir o pausar") { viewModel.press(.mediaPlayPause, strong: true) }
                    IconKey(systemName: "forward.fill", size: 52, accessibilityLabel: "Avanzar") { viewModel.press(.mediaFastForward) }
                }
                HStack(spacing: 12) {
                    IconKey(systemName: "keyboard", size: 52, accessibilityLabel: "Teclado") { sheet = .keyboard }
                    IconKey(systemName: "magnifyingglass", size: 52, accessibilityLabel: "Buscar en el televisor") { viewModel.press(.search) }
                    IconKey(systemName: "slider.horizontal.3", size: 52, accessibilityLabel: "Ajustes rápidos del televisor") { viewModel.press(.settings) }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Sin televisor

    private var onboarding: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Palette.accent)
            VStack(spacing: 8) {
                Text("Conecta tu televisor").font(.title2.bold()).foregroundStyle(Palette.primaryText)
                Text("Busca tu Android TV o Google TV en la red Wi‑Fi y empareja con un código de 6 caracteres. Sin cuentas ni registros.")
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Palette.secondaryText)
            }
            Button { sheet = .settings } label: {
                Label("Buscar televisores", systemImage: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26).padding(.vertical, 14)
                    .glassSurface(Capsule(), tint: Palette.accent)
            }
            Spacer()
        }
        .padding(30)
    }
}
