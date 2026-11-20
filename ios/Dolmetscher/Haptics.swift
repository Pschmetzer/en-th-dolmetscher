// Haptics.swift – kurze Vibrationen als Rückmeldung, damit man beim Reden nicht aufs Display schauen muss.
import UIKit

@MainActor
enum Haptics {
    nonisolated(unsafe) static var enabled = true

    // Geteilte Generatoren: ein neuer je Aufruf spürt die erste Rückmeldung verzögert; `prepare()` hält die Taptic Engine bereit.
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notify = UINotificationFeedbackGenerator()

    nonisolated(unsafe) private static var throttle = HapticThrottle()

    private static func impact(_ g: UIImpactFeedbackGenerator, _ intensity: CGFloat = 1) {
        guard enabled, throttle.allow(at: Date()) else { return }
        g.impactOccurred(intensity: intensity)
        g.prepare()
    }

    private static func notification(_ t: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }   // Hinweise (Erfolg/Warnung/Fehler) nie drosseln
        notify.notificationOccurred(t)
        notify.prepare()
    }

    static func tap() { impact(light) }
    static func heard() { impact(soft) }
    static func command() { impact(rigid) }
    /// „Langsam wiederholen“: etwas weicher, damit man es auch ohne Blick aufs Display merkt.
    static func slow() { impact(medium, 0.6) }
    static func success() { notification(.success) }
    static func warning() { notification(.warning) }
    static func error() { notification(.error) }
}
