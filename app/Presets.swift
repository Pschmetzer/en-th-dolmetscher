// Presets.swift – Szenario-Presets (presets/*.json) für Auswahl und Schnellsätze.
// Die Engine hat kein Ereignis mit der Liste; die App liest dieselben Dateien wie die Engine:
// mitgelieferte im App-Bundle, eigene in ~/Library/Application Support/Dolmetscher/presets (gleiche id ersetzt).
import Foundation

struct Preset: Identifiable, Equatable {
    let id: String
    let names: [String: String]
    /// Schnellsätze des Presets: englischer und thailändischer Text.
    let phrases: [(en: String, th: String)]

    var name: String { names[L.lang.rawValue] ?? names["en"] ?? id }

    static func == (a: Preset, b: Preset) -> Bool { a.id == b.id && a.names == b.names }

    /// Gleiche Grenzen wie die Engine (presets.py): id a-z0-9_- bis 32 Zeichen, Texte gekürzt.
    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, (1...32).contains(id.count),
              id.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }),
              let names = json["names"] as? [String: String], names["en"] != nil else { return nil }
        self.id = id
        self.names = names.mapValues { String($0.prefix(40)) }
        let raw = json["phrases"] as? [[String: Any]] ?? []
        phrases = raw.prefix(50).compactMap { d in
            guard let en = d["en"] as? String, let th = d["th"] as? String else { return nil }
            return (String(en.prefix(200)), String(th.prefix(200)))
        }
    }
}

enum PresetCatalog {
    /// Einmal pro App-Start gelesen (eigene Dateien werden auch von der Engine erst beim Wechsel gelesen).
    static let all: [Preset] = load()

    private static func load() -> [Preset] {
        var byID: [String: Preset] = [:]
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("presets")) }
        dirs.append(Paths.support.appendingPathComponent("presets"))
        let fm = FileManager.default
        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "json" {
                guard let d = try? Data(contentsOf: f), d.count < 200_000,
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let p = Preset(json: o) else { continue }
                byID[p.id] = p   // eigene Datei (später gelesen) ersetzt die mitgelieferte
            }
        }
        return byID.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
