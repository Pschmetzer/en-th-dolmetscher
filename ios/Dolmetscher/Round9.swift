// Round9.swift – kleine, testbare Bausteine der Runde 9 (Export, Satzbuch-Suche, Unterbrechungen).
import Foundation

/// CSV-Zellen gegen Formel-Einschleusung schützen: Excel/Numbers führen Zellen aus, die mit = + - @ (oder Tab/CR)
/// beginnen. Ein vorangestelltes ' macht daraus Text. Ein Gesprächstext wie „=1+1“ bleibt so lesbar, aber harmlos.
enum CSVSafe {
    private static let dangerous: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    static func cell(_ s: String) -> String {
        guard let first = s.first, dangerous.contains(first) else { return s }
        return "'" + s
    }

    /// Dateiname mit Datum (`Dolmetscher-2026-03-10.csv`), damit mehrere Exporte sich nicht überschreiben.
    static func fileName(now: Date = Date(), calendar: Calendar = .current) -> String {
        "Dolmetscher-\(StudyLog.key(now, calendar: calendar)).csv"
    }
}

/// Suche im Satzbuch: ohne Groß-/Kleinschreibung, Akzente und Breite der Zeichen; mehrere Wörter müssen alle
/// vorkommen (in beliebiger Reihenfolge, auch über verschiedene Felder wie Englisch und Umschrift verteilt).
enum PhraseSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func matches(query: String, fields: [String]) -> Bool {
        let tokens = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = fields.map(fold).joined(separator: "\n")
        return tokens.allSatisfy { haystack.contains($0) }
    }
}
