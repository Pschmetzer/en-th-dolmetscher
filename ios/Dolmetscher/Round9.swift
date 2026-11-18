// Round9.swift – kleine, testbare Bausteine der Runde 9 (Export, Satzbuch-Suche, Unterbrechungen).
import Foundation
import SwiftUI

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

/// Sprechtempo: „langsam“ und „deutlich“ als reine Rechnung (Testbar, von `Model.enqueueSpeech` benutzt).
enum SpeechRate {
    static let slowFactor: Double = 0.65
    static let slowFloor: Double = 0.4
    static let clearCeiling: Double = 0.8

    static func effective(rate: Double, slow: Bool, clear: Bool) -> Double {
        slow ? max(slowFloor, rate * slowFactor) : clear ? min(rate, clearCeiling) : rate
    }
}

enum IPadLayout {
    /// Die Werkzeugspalte wächst mit, aber nie so weit, dass das Gespräch schmal wird (iPad Pro 13" im Querformat).
    static let toolsMaxWidth: CGFloat = 440
}

/// Kurzanleitung in der Hilfe: Schritte in der Reihenfolge, in der man sie braucht.
enum HelpGuide {
    static let steps: [(icon: String, title: String, body: String)] = [
        ("mic.fill", "help_s1_t", "help_s1_b"),
        ("rectangle.split.1x2", "help_s2_t", "help_s2_b"),
        ("tortoise", "help_s3_t", "help_s3_b"),
        ("lock.shield", "help_s4_t", "help_s4_b"),
        ("hand.tap", "help_s5_t", "help_s5_b"),
    ]
}

struct HelpGuideCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(T("help_title"), systemImage: "questionmark.circle").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(HelpGuide.steps, id: \.title) { s in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: s.icon).frame(width: 28).foregroundStyle(.tint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T(s.title)).font(.callout.weight(.semibold))
                        Text(T(s.body)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
