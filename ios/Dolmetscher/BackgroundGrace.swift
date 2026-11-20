// BackgroundGrace.swift – kurze Gnadenfrist im Hintergrund (beginBackgroundTask) mit Ablauf-Handler.
// Ohne expirationHandler beendet iOS die App, wenn die Frist abläuft, ohne dass die Aufgabe beendet wurde.
import UIKit

@MainActor
final class BackgroundGrace {
    private var id: UIBackgroundTaskIdentifier = .invalid

    /// Startet die Frist. `onExpire` läuft, kurz bevor iOS die Zeit streicht (Abbau abbrechen oder aufräumen).
    init(name: String, onExpire: @escaping @MainActor () -> Void = {}) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Der Handler läuft auf dem Hauptthread; die Frist muss hier zwingend beendet werden.
            MainActor.assumeIsolated {
                onExpire()
                self?.end()
            }
        }
    }

    /// Läuft die Frist noch?
    var isActive: Bool { id != .invalid }

    /// Restzeit im Hintergrund in Sekunden (unbegrenzt = `.infinity`, solange die App im Vordergrund ist).
    var remaining: TimeInterval { UIApplication.shared.backgroundTimeRemaining }

    /// Beendet die Frist genau einmal (mehrfaches Aufrufen ist harmlos).
    func end() {
        guard id != .invalid else { return }
        let t = id
        id = .invalid
        UIApplication.shared.endBackgroundTask(t)
    }
}
