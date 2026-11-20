// SearchDebounce.swift – Eingabe verzögert übernehmen (Suchfeld im Verlauf): erst nach einer kurzen Tipppause wird gefiltert,
// nicht bei jedem Zeichen. Nur Foundation; getestet in swift-tests.
import Foundation

@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?
    private(set) var runs = 0

    /// Plant `action` nach `delay` Sekunden; ein neuer Aufruf davor verwirft den alten.
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.runs += 1
            action()
        }
    }

    /// Verwirft eine geplante Aktion (z. B. wenn die Eingabe sofort übernommen wird).
    func cancel() { task?.cancel(); task = nil }
}

enum SearchDebounce {
    static let delay: TimeInterval = 0.2

    /// Leere Eingabe (Zurücksetzen, Esc) gilt sofort, alles andere nach der Tipppause.
    static func isImmediate(_ draft: String) -> Bool { draft.isEmpty }
}
