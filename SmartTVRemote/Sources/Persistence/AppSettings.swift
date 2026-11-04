import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: return "Oscuro"
        case .light: return "Claro"
        case .system: return "Sistema"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

/// Preferencias del usuario (persistidas en UserDefaults).
final class AppSettings: ObservableObject {
    @AppStorage("settings.haptics") var hapticsEnabled = true { willSet { objectWillChange.send() } }
    @AppStorage("settings.sounds") var soundsEnabled = false { willSet { objectWillChange.send() } }
    @AppStorage("settings.autoReconnect") var autoReconnect = true { willSet { objectWillChange.send() } }
    @AppStorage("settings.theme") private var themeRaw = AppTheme.dark.rawValue { willSet { objectWillChange.send() } }

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .dark }
        set { themeRaw = newValue.rawValue }
    }
}
