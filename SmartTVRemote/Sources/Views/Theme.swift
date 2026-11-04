import SwiftUI

/// Paleta adaptable a tema oscuro (principal) y claro.
enum Palette {
    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let backgroundTop = dynamic(dark: UIColor(white: 0.07, alpha: 1), light: UIColor(white: 0.97, alpha: 1))
    static let backgroundBottom = dynamic(dark: UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1), light: UIColor(white: 0.88, alpha: 1))
    static let surface = dynamic(dark: UIColor(white: 1, alpha: 0.075), light: UIColor(white: 0, alpha: 0.055))
    static let surfacePressed = dynamic(dark: UIColor(white: 1, alpha: 0.18), light: UIColor(white: 0, alpha: 0.13))
    static let stroke = dynamic(dark: UIColor(white: 1, alpha: 0.12), light: UIColor(white: 0, alpha: 0.08))
    static let primaryText = dynamic(dark: .white, light: UIColor(white: 0.08, alpha: 1))
    static let secondaryText = dynamic(dark: UIColor(white: 1, alpha: 0.55), light: UIColor(white: 0, alpha: 0.5))
    static let dpadTop = dynamic(dark: UIColor(white: 0.16, alpha: 1), light: UIColor(white: 0.93, alpha: 1))
    static let dpadBottom = dynamic(dark: UIColor(white: 0.09, alpha: 1), light: UIColor(white: 0.84, alpha: 1))
    static let accent = Color(red: 0.30, green: 0.56, blue: 1.0)
    static let connected = Color(red: 0.20, green: 0.83, blue: 0.42)
    static let disconnected = Color(white: 0.5)
    static let connecting = Color(red: 1.0, green: 0.74, blue: 0.2)
    static let danger = Color(red: 1.0, green: 0.33, blue: 0.3)
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Palette.backgroundTop, Palette.backgroundBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension View {
    /// Superficie translúcida con borde sutil y sombra: da profundidad a los botones.
    func glassSurface<S: InsettableShape>(_ shape: S, pressed: Bool = false, tint: Color? = nil) -> some View {
        self
            .background(
                shape.fill(tint?.opacity(pressed ? 0.9 : 0.75) ?? (pressed ? Palette.surfacePressed : Palette.surface))
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Palette.stroke, Palette.stroke.opacity(0.15)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .shadow(color: .black.opacity(pressed ? 0.1 : 0.28), radius: pressed ? 2 : 8, y: pressed ? 1 : 4)
    }
}
