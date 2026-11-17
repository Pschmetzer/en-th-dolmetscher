// Storage.swift – Dateiablage und kleine, testbare Helfer ohne Oberfläche.
import Foundation

/// Gespeicherte JSON-Dateien (Verlauf, Favoriten, Notfallkarte) in Application Support.
/// Laden unterscheidet „fehlt“, „nicht lesbar“ (Gerät gesperrt, Datenschutzklasse) und „kaputt“ –
/// nur bei „fehlt“ und „kaputt“ darf mit neuem Inhalt überschrieben werden.
struct JSONStore: Sendable {
    enum Loaded<T> {
        case missing, ok(T), unreadable, corrupt
        var value: T? { if case .ok(let v) = self { return v }; return nil }
    }

    let dir: URL

    static let standard = JSONStore(dir: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])

    func url(_ name: String) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    func load<T: Decodable>(_ type: T.Type, _ name: String) -> Loaded<T> {
        let u = url(name)
        guard FileManager.default.fileExists(atPath: u.path) else { return .missing }
        guard let data = try? Data(contentsOf: u) else { return .unreadable }
        guard let v = try? JSONDecoder().decode(T.self, from: data) else { return .corrupt }
        return .ok(v)
    }

    @discardableResult
    func store<T: Encodable>(_ value: T, _ name: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        // „UntilFirstUserAuthentication“: nach dem ersten Entsperren seit dem Neustart lesbar – auch wenn die
        // App gesperrt startet (Siri, Action-Taste) oder im Hintergrund zuhört.
        var u = url(name)
        guard (try? data.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return false }
        // Nicht ins iCloud-/Computer-Backup (566): „bleibt nur auf diesem iPhone“. `.atomic` ersetzt die Datei,
        // daher nach jedem Schreiben neu setzen.
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? u.setResourceValues(rv)
        return true
    }

    /// Liste tolerant laden (604): ein kaputter oder unbekannter Eintrag kostet nur diesen Eintrag, nicht alles.
    /// Fehlen Einträge, bleibt eine Sicherung `name.bak-…` liegen, bevor neu geschrieben wird.
    func loadLossy<T: Decodable>(_ type: T.Type, _ name: String) -> Loaded<[T]> {
        let u = url(name)
        guard FileManager.default.fileExists(atPath: u.path) else { return .missing }
        guard let data = try? Data(contentsOf: u) else { return .unreadable }
        guard let rows = try? JSONDecoder().decode([Lossy<T>].self, from: data) else { return .corrupt }
        let ok = rows.compactMap(\.value)
        if ok.count < rows.count {
            let stamp = Int(Date().timeIntervalSince1970)
            try? FileManager.default.copyItem(at: u, to: url("\(name).bak-\(stamp)"))
        }
        return .ok(ok)
    }

    /// Kaputte Datei beiseitelegen statt überschreiben.
    func quarantine(_ name: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.moveItem(at: url(name), to: url("\(name).corrupt-\(stamp)"))
    }

    func remove(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }

    /// Dateien entfernen, deren Name so beginnt – auch beiseitegelegte Kopien („history.json.corrupt-…“).
    func removeAll(prefixes: [String]) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names where prefixes.contains(where: { n.hasPrefix($0) }) { remove(n) }
    }
}

/// Ein Listeneintrag, der beim Dekodieren scheitern darf (nil statt Abbruch der ganzen Liste).
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Zuletzt Gelöschtes für eine Weile zurückholbar halten („Verlauf leeren“ – ein Verhörer genügt).
struct UndoBuffer<T> {
    private(set) var saved: T?
    private(set) var until: Date = .distantPast

    mutating func keep(_ value: T, now: Date = Date(), seconds: TimeInterval = 8) {
        saved = value
        until = now.addingTimeInterval(seconds)
    }

    func available(at now: Date = Date()) -> Bool { saved != nil && now < until }

    mutating func take(at now: Date = Date()) -> T? {
        defer { saved = nil }
        return available(at: now) ? saved : nil
    }

    mutating func drop() { saved = nil }
}

/// Beträge wie auf thailändischen Preisschildern: „1,200“ = 1200 (Tausender-Komma), „1.200“ = 1200,
/// „12,5“ = 12.5 (Dezimal-Komma), „1,200.50“ = 1200.5. Leerzeichen und ฿ werden ignoriert.
enum AmountParser {
    static func parse(_ raw: String) -> Double? {
        var s = raw.filter { !$0.isWhitespace && $0 != "฿" && $0 != "\u{00A0}" && $0 != "'" }
        guard !s.isEmpty else { return nil }
        let commas = s.filter { $0 == "," }.count, dots = s.filter { $0 == "." }.count
        func groupedThousands(_ sep: Character) -> Bool {
            // 1,200 / 12,000 / 1,200,000: erste Gruppe 1–3 Ziffern, dann nur Dreiergruppen
            let parts = s.split(separator: sep, omittingEmptySubsequences: false)
            guard parts.count >= 2, let f = parts.first, (1...3).contains(f.count) else { return false }
            return parts.dropFirst().allSatisfy { $0.count == 3 }
        }
        if commas > 0 && dots > 0 {
            // Das letzte Zeichen von beiden ist das Dezimalzeichen.
            let lastComma = s.lastIndex(of: ",")!, lastDot = s.lastIndex(of: ".")!
            if lastDot > lastComma { s.removeAll { $0 == "," } } else {
                s.removeAll { $0 == "." }; s = s.replacingOccurrences(of: ",", with: ".")
            }
        } else if commas > 0 {
            if commas > 1 || groupedThousands(",") { s.removeAll { $0 == "," } } else { s = s.replacingOccurrences(of: ",", with: ".") }
        } else if dots > 1 || (dots == 1 && groupedThousands(".") && s.first != "0") {
            // „1.200“ – Punkt als Tausendertrennzeichen (de); „0.026“ bleibt ein Dezimalbruch
            s.removeAll { $0 == "." }
        }
        return Double(s)
    }
}
