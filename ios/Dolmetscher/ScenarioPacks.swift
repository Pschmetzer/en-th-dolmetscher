// ScenarioPacks.swift – Szenario-Pakete aus ../presets/*.json (dieselben Dateien wie Mac-App und Engine).
// Das Xcode-Projekt kopiert den Ordner als Ordner-Referenz ins Bundle („presets/“); gepflegt wird nur dort.
import Foundation

/// Ein Paket wie „Arzt“ oder „Polizei“: Name, Kulturhinweis und geprüfte Sätze (Englisch -> Thai).
struct ScenarioPack: Decodable, Identifiable, Sendable {
    struct Line: Decodable, Sendable {
        var en: String
        var th: String
        /// Sicherheitskritisch (Allergie, Notruf, …): hervorheben und zuerst zeigen.
        var critical: Bool?
    }

    var id: String
    var names: [String: String]
    /// Kulturhinweis je Sprache (de/en; sonst Englisch).
    var note: [String: String]?
    var phrases: [Line]

    /// Kategorie-Schlüssel im Satzbuch (getrennt von den eingebauten Kategorien).
    var key: String { Self.prefix + id }
    static let prefix = "pack."

    /// Name in der Oberflächensprache: aus der Datei (de/en/th), sonst aus L10n.packNames, sonst Englisch.
    func name(_ ui: String) -> String { names[ui] ?? L10n.packNames[id]?[ui] ?? names["en"] ?? id }
    func noteText(_ ui: String) -> String? {
        guard let note else { return nil }
        let t = note[ui] ?? note["en"]
        return (t?.isEmpty ?? true) ? nil : t
    }

    var icon: String { Self.icons[id] ?? "square.stack" }

    static let icons: [String: String] = [
        "bank": "building.columns.circle", "doctor": "stethoscope", "hotel": "bed.double", "lostchild": "figure.and.child.holdinghands",
        "office": "briefcase", "pharmacy": "pills", "police": "shield", "rental": "key", "restaurant": "fork.knife",
        "scooter": "scooter", "shopping": "bag", "spa": "leaf", "taxi": "car", "temple": "building.columns",
        "transport": "tram", "travel": "airplane",
    ]

    /// Sätze als Satzbuch-Einträge, kritische zuerst (sonst Reihenfolge der Datei).
    var asPhrases: [Phrase] {
        let crit = phrases.filter { $0.critical == true }
        let rest = phrases.filter { $0.critical != true }
        return (crit + rest).map {
            Phrase(en: $0.en, th: $0.th, roman: "", category: key, critical: $0.critical == true ? true : nil, pack: id)
        }
    }

    /// Alle Pakete eines Bundles, nach Dateiname sortiert. Ungültige Dateien werden übersprungen.
    static func load(_ bundle: Bundle) -> [ScenarioPack] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "presets") ?? []
        return load(urls)
    }

    static func load(_ urls: [URL]) -> [ScenarioPack] {
        urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let p = try? JSONDecoder().decode(ScenarioPack.self, from: data), !p.phrases.isEmpty else { return nil }
            return p
        }
    }
}
