import SwiftUI

/// Emparejamiento con código PIN mostrado en el televisor.
struct PairingView: View {
    let device: TVDevice
    @EnvironmentObject private var connection: TVConnectionManager
    @StateObject private var pairing = PairingManager()
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Button("Cancelar") { pairing.cancel(); dismiss() }.fontWeight(.semibold)
            }
            Spacer(minLength: 0)
            Image(systemName: "lock.shield.fill").font(.system(size: 46)).foregroundStyle(Palette.accent)
            Text("Emparejar \(device.name)").font(.title2.bold()).multilineTextAlignment(.center)

            content

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(AppBackground())
        .interactiveDismissDisabled(pairing.phase == .verifying)
        .onAppear { pairing.begin(device: device) }
        .onDisappear { pairing.cancel() }
        .onChange(of: pairing.phase) { _, phase in
            switch phase {
            case .waitingForCode: focused = true
            case .success:
                connection.pairingCompleted(device)
                Task { try? await Task.sleep(nanoseconds: 900_000_000); dismiss() }
            default: break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pairing.phase {
        case .idle, .connecting:
            VStack(spacing: 12) {
                ProgressView()
                Text("Conectando con el televisor…").foregroundStyle(Palette.secondaryText)
            }
        case .waitingForCode, .verifying:
            VStack(spacing: 16) {
                Text("Escribe el código de 6 caracteres que aparece ahora en la pantalla de tu televisor.")
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Palette.secondaryText)
                TextField("000000", text: $code)
                    .focused($focused)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .padding(.vertical, 14)
                    .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: code) { _, v in
                        let filtered = String(v.uppercased().filter { $0.isHexDigit }.prefix(6))
                        if filtered != v { code = filtered }
                    }
                    .disabled(pairing.phase == .verifying)
                Button {
                    pairing.submit(code: code)
                } label: {
                    HStack {
                        if pairing.phase == .verifying { ProgressView().tint(.white) }
                        Text(pairing.phase == .verifying ? "Verificando…" : "Emparejar").font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .glassSurface(Capsule(), tint: Palette.accent)
                }
                .disabled(code.count != 6 || pairing.phase == .verifying)
                .opacity(code.count == 6 ? 1 : 0.5)
            }
        case .success:
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Palette.connected)
                Text("¡Emparejado!").font(.headline)
            }
        case .failed(let error):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(Palette.danger)
                Text(error.errorDescription ?? "Error").font(.headline).multilineTextAlignment(.center)
                if let hint = error.recoverySuggestion {
                    Text(hint).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Palette.secondaryText)
                }
                Button {
                    code = ""
                    pairing.begin(device: device)
                } label: {
                    Text("Reintentar").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .glassSurface(Capsule(), tint: Palette.accent)
                }
            }
        }
    }
}
