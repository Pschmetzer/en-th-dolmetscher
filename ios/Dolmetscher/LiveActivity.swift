// LiveActivity.swift – startet, aktualisiert und beendet die Live-Aktivität beim Zuhören (Sperrbildschirm,
// Dynamic Island). Aktualisiert nur bei Zustandswechseln, gebündelt (ActivityKit drosselt häufige Updates).
import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<ListeningActivityAttributes>?
    private var last: ListeningActivityAttributes.ContentState?
    private var pending: Task<Void, Never>?

    private init() {
        // Reste eines früheren Laufs (App beendet, während sie zuhörte) aufräumen.
        Task {
            for a in Activity<ListeningActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func update(_ state: ListeningActivityAttributes.ContentState, pair: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard state != last else { return }
        guard let activity else {
            // `last` erst nach Erfolg merken: scheitert die Anfrage (Limit, Hintergrund), gilt derselbe Zustand
            // beim nächsten Versuch nicht als „schon gesendet“.
            if let a = try? Activity.request(attributes: ListeningActivityAttributes(pair: pair),
                                             content: .init(state: state, staleDate: nil), pushType: nil) {
                self.activity = a
                last = state
            }
            return
        }
        last = state
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func end() {
        pending?.cancel()
        last = nil
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
