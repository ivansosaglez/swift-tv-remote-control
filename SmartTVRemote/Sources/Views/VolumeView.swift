import SwiftUI

/// Módulo vertical de volumen estilo iOS: VOL+ arriba, VOL− abajo y MUTE en el centro.
/// El nivel real del televisor (si lo informa) se muestra como relleno de la cápsula.
struct VolumeView: View {
    @ObservedObject var viewModel: RemoteViewModel
    @ObservedObject var connection: TVConnectionManager

    private let width: CGFloat = 78

    var body: some View {
        let volume = connection.volume
        let muted = volume?.muted == true
        ZStack(alignment: .bottom) {
            Capsule().fill(Palette.surface)

            // Relleno de nivel
            if let volume {
                GeometryReader { geo in
                    Rectangle()
                        .fill(LinearGradient(colors: [Palette.accent.opacity(muted ? 0.12 : 0.5), Palette.accent.opacity(muted ? 0.05 : 0.25)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: geo.size.height * volume.fraction)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .animation(.easeOut(duration: 0.25), value: volume)
                }
                .clipShape(Capsule())
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                step("plus", "Subir volumen", .volumeUp)
                Spacer(minLength: 0)
                PressableKey(action: { viewModel.press(.volumeMute) }) { pressed in
                    VStack(spacing: 3) {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(muted ? Palette.danger : Palette.primaryText)
                        if let volume {
                            Text("\(volume.level)")
                                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                    .frame(width: width - 12, height: 56)
                    .background(Capsule().fill(pressed ? Palette.surfacePressed : .clear))
                }
                .accessibilityLabel(muted ? "Quitar silencio" : "Silenciar")
                Spacer(minLength: 0)
                step("minus", "Bajar volumen", .volumeDown)
            }
            .padding(.vertical, 6)
        }
        .frame(width: width)
        .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volumen")
    }

    private func step(_ symbol: String, _ label: String, _ key: AndroidKey) -> some View {
        PressableKey(repeating: true, action: { viewModel.press(key) }) { pressed in
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
                .frame(width: width - 12, height: 62)
                .background(Capsule().fill(pressed ? Palette.surfacePressed : .clear))
        }
        .accessibilityLabel(label)
    }
}
