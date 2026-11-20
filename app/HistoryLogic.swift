// HistoryLogic.swift – Runde 14: Gruppierung, Filter und Verwaltung des gespeicherten Verlaufs.
// Reine Logik ohne UI (nur Foundation), per swiftc getestet. Datengrundlage ist ausschließlich der JSON-Export
// der Engine (`--history-export json`, docs/PROTOKOLL.md „Gesprächsverlauf“): time, session, lang, text,
// translation, translit, confidence, provider, role, speaker.
import Foundation

/// Eine gespeicherte Zeile des Verlaufs.
struct HistoryRow: Equatable {
    var time: Date
    var session: String
    var lang: String
    var text: String
    var translation: String
    var translit: String
    var confidence: Double?
    var provider: String?
    var role: String?
    var speaker: String?
}

/// Eine Sitzung (Engine: neue Sitzung nach 30 min Pause oder Tageswechsel).
struct HistorySession: Equatable, Identifiable {
    var id: String
    var start: Date
    var rows: [HistoryRow]
}

/// Lokale Angaben des Nutzers zu Sitzungen: eigener Name, Favorit, aus der Liste entfernt.
/// Die Engine kennt keine Einzel-Löschung (nur --history-purge/--history-clear): „Entfernen“ blendet nur aus.
struct HistoryMeta: Equatable, Codable {
    var names: [String: String] = [:]
    var favorites: Set<String> = []
    var hidden: Set<String> = []
}

struct HistoryFilter: Equatable {
    var query = ""
    var lang = ""              // "" = alle
    var role = ""              // "", "me" oder "other" (Richtung im Zwei-Personen-Modus)
    var numberWarning = false
    var weakTranslation = false
    var favoritesOnly = false
    var isActive: Bool {
        !query.isEmpty || !lang.isEmpty || !role.isEmpty || numberWarning || weakTranslation || favoritesOnly
    }
}

struct HistoryDay: Equatable, Identifiable {
    var day: Date              // Beginn des Tages
    var sessions: [HistorySession]
    var id: Date { day }
}

enum HistoryLogic {
    static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        if let d = isoWithFraction.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }

    /// Zeilen aus dem JSON-Export. Ungültige Einträge werden übersprungen, nie geraten.
    static func parse(_ data: Data) -> [HistoryRow] {
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return arr.compactMap(row)
    }

    private static func row(_ o: [String: Any]) -> HistoryRow? {
        guard let t = o["time"] as? String, let date = parseDate(t), let session = o["session"] as? String else { return nil }
        let role = o["role"] as? String
        return HistoryRow(time: date, session: session, lang: o["lang"] as? String ?? "",
                          text: o["text"] as? String ?? "", translation: o["translation"] as? String ?? "",
                          translit: o["translit"] as? String ?? "", confidence: o["confidence"] as? Double,
                          provider: o["provider"] as? String, role: role == "me" || role == "other" ? role : nil,
                          speaker: o["speaker"] as? String)
    }

    /// Sitzungen, neueste zuerst; Zeilen innerhalb einer Sitzung nach Zeit.
    static func sessions(_ rows: [HistoryRow]) -> [HistorySession] {
        var by: [String: [HistoryRow]] = [:]
        for r in rows { by[r.session, default: []].append(r) }
        var out: [HistorySession] = []
        for (id, list) in by {
            let sorted = list.sorted { $0.time < $1.time }
            out.append(HistorySession(id: id, start: sorted[0].time, rows: sorted))
        }
        return out.sorted { $0.start != $1.start ? $0.start > $1.start : $0.id < $1.id }
    }

    /// Nach Tag gruppiert (Tage und Sitzungen neueste zuerst).
    static func days(_ sessions: [HistorySession], calendar: Calendar = .current) -> [HistoryDay] {
        var out: [HistoryDay] = []
        for s in sessions {
            let d = calendar.startOfDay(for: s.start)
            if let i = out.firstIndex(where: { $0.day == d }) { out[i].sessions.append(s) }
            else { out.append(HistoryDay(day: d, sessions: [s])) }
        }
        return out.sorted { $0.day > $1.day }
    }

    // MARK: Merkmale einer Zeile

    private static func digitRuns(_ s: String) -> [String] {
        var runs: [String] = []
        var cur = ""
        for ch in s {
            if let v = ch.wholeNumberValue, ch.isNumber, v >= 0, v <= 9 { cur.append(String(v)) }
            else if !cur.isEmpty { runs.append(cur); cur = "" }
        }
        if !cur.isEmpty { runs.append(cur) }
        return runs.sorted()
    }

    /// Ziffern in Original und Übersetzung weichen ab. Die Engine speichert `num_warn` nicht; dies ist die
    /// einfache Näherung der App (nur wenn eine Seite Ziffern hat und es eine Übersetzung gibt).
    static func hasNumberWarning(_ r: HistoryRow) -> Bool {
        if r.translation.isEmpty { return false }
        let a = digitRuns(r.text), b = digitRuns(r.translation)
        return (!a.isEmpty || !b.isEmpty) && a != b
    }

    /// Schwache Übersetzung: der Anbieter MyMemory (wie die Blase „weak_mt“).
    static func isWeak(_ r: HistoryRow) -> Bool { r.provider == "mymemory" }

    static func matches(_ r: HistoryRow, _ f: HistoryFilter) -> Bool {
        if !f.lang.isEmpty && r.lang != f.lang { return false }
        if !f.role.isEmpty && r.role != f.role { return false }
        if f.numberWarning && !hasNumberWarning(r) { return false }
        if f.weakTranslation && !isWeak(r) { return false }
        // Leerzeichen am Rand zählen nicht („hello “ beim Tippen); gesucht wird auch in der Umschrift (Thai → Latein)
        let q = f.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        let o: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]   // „cafe“ findet „café“
        return [r.text, r.translation, r.translit].contains { $0.range(of: q, options: o) != nil }
    }

    /// Zeilen mit passender Suche/Filter-Auswahl; ohne aktiven Zeilenfilter alle.
    static func rows(of s: HistorySession, _ f: HistoryFilter) -> [HistoryRow] {
        s.rows.filter { matches($0, f) }
    }

    /// Sitzungen, die nach Filter noch Treffer haben (ohne ausgeblendete), plus Gesamt-Trefferzahl.
    static func apply(_ all: [HistorySession], filter f: HistoryFilter, meta: HistoryMeta)
        -> (sessions: [HistorySession], hits: Int) {
        var out: [HistorySession] = []
        var hits = 0
        for s in all {
            if meta.hidden.contains(s.id) { continue }
            if f.favoritesOnly && !meta.favorites.contains(s.id) { continue }
            let kept = rows(of: s, f)
            if kept.isEmpty { continue }
            hits += kept.count
            out.append(HistorySession(id: s.id, start: s.start, rows: kept))
        }
        return (out, hits)
    }

    // MARK: Anzeige

    /// Eigener Name, sonst leer (die Ansicht setzt dann Uhrzeit und Anzahl ein).
    static func name(_ s: HistorySession, _ meta: HistoryMeta) -> String {
        (meta.names[s.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Erster Satz der Sitzung, gekürzt, für die Vorschau.
    static func preview(_ s: HistorySession, limit: Int = 80) -> String {
        let first = s.rows.first { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let t = (first?.text ?? "").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > limit ? String(t.prefix(limit)) + "…" : t
    }

    /// Sprachen, die in den Sitzungen vorkommen (für das Filtermenü), alphabetisch.
    static func languages(_ sessions: [HistorySession]) -> [String] {
        var set = Set<String>()
        for s in sessions { for r in s.rows where !r.lang.isEmpty { set.insert(r.lang) } }
        return set.sorted()
    }

    // MARK: Verwalten (mit Rückgängig)

    /// Name setzen; leer entfernt ihn. Länge begrenzt.
    static func renamed(_ meta: HistoryMeta, id: String, to name: String) -> HistoryMeta {
        var m = meta
        let t = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        if t.isEmpty { m.names[id] = nil } else { m.names[id] = t }
        return m
    }

    static func toggledFavorite(_ meta: HistoryMeta, id: String) -> HistoryMeta {
        var m = meta
        if m.favorites.contains(id) { m.favorites.remove(id) } else { m.favorites.insert(id) }
        return m
    }

    static func hiding(_ meta: HistoryMeta, id: String) -> HistoryMeta {
        var m = meta
        m.hidden.insert(id)
        return m
    }

    static func restoring(_ meta: HistoryMeta, id: String) -> HistoryMeta {
        var m = meta
        m.hidden.remove(id)
        return m
    }

    /// Angaben zu Sitzungen, die es nicht mehr gibt (Engine hat sie gelöscht), entfernen.
    static func pruned(_ meta: HistoryMeta, keeping ids: Set<String>) -> HistoryMeta {
        var m = meta
        m.names = m.names.filter { ids.contains($0.key) }
        m.favorites = m.favorites.intersection(ids)
        m.hidden = m.hidden.intersection(ids)
        return m
    }

    /// Nächste Auswahl nach Pfeiltaste (delta ±1), begrenzt auf die Liste.
    static func moved(_ ids: [String], from current: String?, by delta: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let c = current, let i = ids.firstIndex(of: c) else { return delta >= 0 ? ids.first : ids.last }
        return ids[max(0, min(ids.count - 1, i + delta))]
    }

    /// Nach dem Entfernen: Nachbar der entfernten Sitzung (nächste, sonst vorige).
    static func neighbor(_ ids: [String], of removed: String) -> String? {
        guard let i = ids.firstIndex(of: removed) else { return nil }
        if i + 1 < ids.count { return ids[i + 1] }
        return i > 0 ? ids[i - 1] : nil
    }
}
