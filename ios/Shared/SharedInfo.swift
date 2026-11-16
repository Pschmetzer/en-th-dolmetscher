// SharedInfo.swift – Code für App und Widget-Erweiterung (beide Ziele kompilieren den Ordner Shared).
// Kein App Group: das Widget liest keine Einstellungen der App. Satzbuch-Daten liegen als phrases.json in beiden
// Bundles, Auswahl und Höflichkeitsform stellt man im Widget selbst ein; Live-Aktivitäten bekommen ihre Daten
// über ActivityKit, Knöpfe laufen als App Intents in der App.
import Foundation

/// Ein Satz des eingebauten Satzbuchs (Englisch -> Thai), mit deutscher Glosse.
struct PhraseRecord: Codable, Hashable, Sendable {
    var category: String
    var en: String
    var de: String?
    /// Thai mit Platzhaltern {p} {q} {i} (Höflichkeitswort, Frage-Ende, „ich“)
    var th: String
    var roman: String
}

enum PhraseData {
    /// Reihenfolge und Symbole der Kategorien.
    static let categories: [(key: String, icon: String)] = [
        ("basics", "hand.wave"), ("food", "fork.knife"), ("transport", "car"), ("shopping", "bag"),
        ("numbers", "clock"), ("money", "banknote"), ("hotel", "bed.double"), ("health", "cross.case"),
        ("temple", "building.columns"),
    ]

    static let all: [PhraseRecord] = load(Bundle.main)

    static func load(_ bundle: Bundle) -> [PhraseRecord] {
        guard let url = bundle.url(forResource: "phrases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([PhraseRecord].self, from: data) else { return [] }
        return list
    }

    /// Platzhalter füllen – gleiche Regeln wie `Politeness.fill` der App.
    static func fill(_ template: String, female: Bool) -> String {
        template.replacingOccurrences(of: "{p}", with: female ? "ค่ะ" : "ครับ")
            .replacingOccurrences(of: "{q}", with: female ? "คะ" : "ครับ")
            .replacingOccurrences(of: "{i}", with: female ? "ฉัน" : "ผม")
    }

    /// Glosse in der Oberflächensprache (Deutsch, sonst Englisch).
    static func gloss(_ r: PhraseRecord, ui: String) -> String { ui == "de" ? (r.de ?? r.en) : r.en }
}
