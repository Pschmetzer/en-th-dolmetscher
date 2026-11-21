// R27Logic.swift – kleine reine Logik der Runde 27 (nur Foundation; getestet in swift-tests):
// Abbruch-Token für asynchrone Prüfungen, Cmd-A-Regel der Mehrfachauswahl, Sprechtexte für Diagramme.
import Foundation

/// Erzeugungs-Zähler: eine abgebrochene oder überholte Prüfung (Schlüsseltest, Selbsttest) darf ihr Ergebnis nicht mehr
/// eintragen, auch wenn der Netz- oder Systemaufruf noch zurückkommt.
struct StaleGuard: Equatable {
    private(set) var generation = 0
    /// Neuer Lauf: macht alle früheren ungültig.
    mutating func begin() -> Int { generation += 1; return generation }
    /// Abbruch (Fenster zu, Knopf „Abbrechen“): macht den laufenden Lauf ungültig.
    mutating func cancel() { generation += 1 }
    func isCurrent(_ token: Int) -> Bool { token == generation }
}

/// Cmd-A in der Mehrfachauswahl-Leiste: nur „alle Blasen wählen“, wenn kein Textfeld bearbeitet wird; sonst bekommt das
/// Feld das Kürzel (Text markieren). Vorher blockierte das Menükürzel der Leiste das Markieren im Eingabefeld.
enum SelectAllShortcut {
    static func shouldSelectBubbles(selecting: Bool, textEditing: Bool) -> Bool { selecting && !textEditing }
}

/// Sprechtexte für Swift-Charts (VoiceOver): ein Satz je Diagramm statt ungelabelter Balken.
enum ChartA11y {
    /// „a 3, b 5“; leer -> „–“. Höchstens `limit` Einträge, der Rest als „… +n“.
    static func values(_ pairs: [(String, Int)], limit: Int = 12) -> String {
        guard !pairs.isEmpty else { return "–" }
        let shown = pairs.prefix(limit).map { "\($0.0) \($0.1)" }.joined(separator: ", ")
        return shown + (pairs.count > limit ? ", … +\(pairs.count - limit)" : "")
    }

    /// „Titel: a 3, b 5“.
    static func summary(title: String, pairs: [(String, Int)], limit: Int = 12) -> String {
        title + ": " + values(pairs, limit: limit)
    }

    /// Nur Stunden mit Einträgen („9 Uhr 4“) – die übrigen 20 stummen Balken würden VoiceOver nur aufhalten.
    static func hourPairs(_ perHour: [Int]) -> [(String, Int)] {
        perHour.enumerated().filter { $0.element > 0 }.map { ("\($0.offset) h", $0.element) }
    }
}
