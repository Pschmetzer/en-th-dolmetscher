// Haptics.swift – kurze Vibrationen als Rückmeldung, damit man beim Reden nicht aufs Display schauen muss.
import UIKit

@MainActor
enum Haptics {
    nonisolated(unsafe) static var enabled = true

    static func tap() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func heard() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func command() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    /// „Langsam wiederholen“: zweimal kurz, damit man es auch ohne Blick aufs Display merkt.
    static func slow() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6) }
    static func success() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
