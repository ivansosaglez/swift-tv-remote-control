import SwiftUI

/// Hoja con el teclado nativo de iOS: lo escrito se transmite en vivo al campo de texto del televisor.
struct KeyboardInputView: View {
    @ObservedObject var viewModel: RemoteViewModel
    @ObservedObject var connection: TVConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var secure = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Teclado").font(.title3.bold())
                Spacer()
                Button("Cerrar") { dismiss() }.fontWeight(.semibold)
            }

            HStack(spacing: 8) {
                Image(systemName: connection.hasFocusedTextField ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(connection.hasFocusedTextField ? Palette.connected : Palette.connecting)
                Text(connection.hasFocusedTextField
                     ? "Campo de texto detectado en el televisor"
                     : "Abre un campo de texto en el televisor (p. ej. la búsqueda de Netflix)")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
                Spacer(minLength: 0)
            }

            HStack {
                Group {
                    if secure {
                        SecureField("Escribe aquí", text: $text)
                    } else {
                        TextField("Escribe aquí", text: $text)
                    }
                }
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { send(.enter) }
                Button { secure.toggle() } label: {
                    Image(systemName: secure ? "eye.slash" : "eye").foregroundStyle(Palette.secondaryText)
                }
                .accessibilityLabel(secure ? "Mostrar texto" : "Ocultar texto")
            }
            .padding(14)
            .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                actionButton("Borrar todo", system: "xmark.circle") { text = "" }
                actionButton("Retroceso", system: "delete.left") { send(.delete) }
                actionButton("Enviar", system: "return", prominent: true) { send(.enter) }
            }

            Text("Para dictar, usa el micrófono del teclado de iOS. Las contraseñas se envían tal cual al televisor.")
                .font(.caption).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(AppBackground())
        .onAppear { focused = true; text = connection.imeField?.value ?? "" }
        .onChange(of: text) { _, newValue in
            if !connection.sendText(newValue) { /* sin campo enfocado: no hay dónde escribir */ }
        }
        .onChange(of: connection.imeField?.fieldCounter) { _, _ in
            // Nuevo campo enfocado en la TV: se parte de su contenido.
            text = connection.imeField?.value ?? ""
        }
    }

    private func send(_ key: AndroidKey) {
        viewModel.press(key, strong: key == .enter)
    }

    private func actionButton(_ title: String, system: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(prominent ? .white : Palette.primaryText)
                .glassSurface(Capsule(), tint: prominent ? Palette.accent : nil)
        }
        .buttonStyle(.plain)
    }
}
