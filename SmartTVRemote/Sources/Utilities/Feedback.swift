import UIKit
import AudioToolbox

/// Respuesta háptica y sonora de las pulsaciones.
@MainActor
final class Feedback {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notifier = UINotificationFeedbackGenerator()
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        light.prepare(); medium.prepare()
    }

    func tap(strong: Bool = false) {
        if settings.hapticsEnabled {
            (strong ? medium : light).impactOccurred()
            (strong ? medium : light).prepare()
        }
        if settings.soundsEnabled { AudioServicesPlaySystemSound(1104) }
    }

    func success() { if settings.hapticsEnabled { notifier.notificationOccurred(.success) } }
    func error() { if settings.hapticsEnabled { notifier.notificationOccurred(.error) } }
}
