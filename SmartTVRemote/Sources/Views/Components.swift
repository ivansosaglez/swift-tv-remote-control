import SwiftUI

/// Botón que reacciona al contacto (touch‑down), no al levantar el dedo, como un mando físico.
/// Opcionalmente repite la acción mientras se mantiene pulsado.
struct PressableKey<Content: View>: View {
    var repeating = false
    var enabled = true
    var action: () -> Void
    @ViewBuilder var content: (Bool) -> Content

    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        content(pressed)
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !pressed else { return }
                        pressed = true
                        action()
                        if repeating {
                            repeatTask = Task {
                                try? await Task.sleep(nanoseconds: 420_000_000)
                                while !Task.isCancelled {
                                    await MainActor.run { action() }
                                    try? await Task.sleep(nanoseconds: 110_000_000)
                                }
                            }
                        }
                    }
                    .onEnded { _ in release() }
            )
            .onDisappear { release() }
            .opacity(enabled ? 1 : 0.4)
            .accessibilityAddTraits(.isButton)
    }

    private func release() {
        pressed = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// Botón redondeado con icono y (opcionalmente) etiqueta.
struct IconKey: View {
    let systemName: String
    var label: String?
    var size: CGFloat = 58
    var tint: Color?
    var repeating = false
    var enabled = true
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        PressableKey(repeating: repeating, enabled: enabled, action: action) { pressed in
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.36, weight: .semibold))
                if let label {
                    Text(label).font(.system(size: 10, weight: .medium)).opacity(0.7)
                }
            }
            .foregroundStyle(tint == nil ? Palette.primaryText : .white)
            .frame(width: size, height: size)
            .glassSurface(RoundedRectangle(cornerRadius: size * 0.34, style: .continuous), pressed: pressed, tint: tint)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Indicador de conexión: verde = conectado, gris = desconectado, ámbar pulsante = conectando.
struct ConnectionDot: View {
    let state: ConnectionState
    @State private var pulse = false

    private var color: Color {
        switch state {
        case .connected: return Palette.connected
        case .connecting, .reconnecting, .pairingRequired: return Palette.connecting
        case .failed: return Palette.danger.opacity(0.9)
        default: return Palette.disconnected
        }
    }

    var body: some View {
        ZStack {
            if state.isBusy {
                Circle().fill(color.opacity(0.35))
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.9)
            }
            Circle().fill(color)
        }
        .frame(width: 9, height: 9)
        .onAppear { startPulse() }
        .onChange(of: state.isBusy) { _, _ in startPulse() }
        .accessibilityHidden(true)
    }

    private func startPulse() {
        pulse = false
        guard state.isBusy else { return }
        withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) { pulse = true }
    }
}

/// Aviso discreto y temporal.
struct ToastView: View {
    let text: String
    var isError = false
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.primaryText)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(isError ? Palette.danger.opacity(0.6) : Palette.stroke))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }
}
