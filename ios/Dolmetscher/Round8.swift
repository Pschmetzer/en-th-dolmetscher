// Round8.swift – kleine, testbare Bausteine der Runde 8 (Netzwechsel, Lernstatistik, zuletzt gesagte Sätze).
import Foundation

/// Lernstatistik: wie viele Karten an welchem Tag beantwortet wurden (nur auf dem Gerät, Teil von learn.json).
struct StudyLog: Codable, Equatable, Sendable {
    /// Tag (`yyyy-MM-dd` im Kalender des Geräts) -> beantwortete Karten.
    var days: [String: Int] = [:]
    /// So viele Tage merkt sich das Protokoll; ältere fallen weg.
    static let keepDays = 400

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    mutating func record(now: Date = Date(), calendar: Calendar = .current) {
        days[Self.key(now, calendar: calendar), default: 0] += 1
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: now) else { return }
        let oldest = Self.key(cutoff, calendar: calendar)
        days = days.filter { $0.key >= oldest }
    }

    func today(now: Date = Date(), calendar: Calendar = .current) -> Int {
        days[Self.key(now, calendar: calendar)] ?? 0
    }

    /// Tage in Folge mit mindestens einer Karte. Heute noch nichts gelernt: die Serie bis gestern zählt weiter.
    func streak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now)
        if today(now: now, calendar: calendar) == 0 {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var n = 0
        while (days[Self.key(day, calendar: calendar)] ?? 0) > 0 {
            n += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }
}

/// Netzwechsel: Sätze, die wegen fehlenden Netzes nicht übersetzt wurden, nach dem Wiederkommen des Netzes nachholen.
enum ReconnectRetry {
    /// Nur Sätze der letzten Minuten (ältere sind nicht mehr Teil des laufenden Gesprächs) und nicht zu viele auf einmal.
    static let window: TimeInterval = 15 * 60
    static let maxCount = 5

    /// Ohne Netz → mit Netz.
    static func cameBack(was: Bool?, now: Bool) -> Bool { was == false && now }

    /// Einträge ohne Übersetzung mit Fehler, älteste zuerst (so bleibt die Reihenfolge des Gesprächs).
    static func pending(_ entries: [Entry], now: Date = Date()) -> [UUID] {
        let open = entries.filter { (e: Entry) -> Bool in
            e.error != nil && e.translation == nil && e.photo != true && !e.text.isEmpty
                && now.timeIntervalSince(e.date) <= window
        }
        return open.suffix(maxCount).map(\.id)
    }
}

extension Phrasebook {
    /// Zuletzt gesagte Satzbuch-Sätze, neueste zuerst, jeder nur einmal. Quelle ist der Verlauf selbst:
    /// Sperre, Aufbewahrung und „Verlauf nicht speichern“ gelten damit automatisch auch hier.
    static func recent(entries: [Entry], in list: [Phrase], limit: Int = 12) -> [Phrase] {
        let byText: [String: Phrase] = Dictionary(list.filter { $0.srcLang == .en }.map { ($0.en, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var out: [Phrase] = []
        for e in entries.reversed() where e.provider == "phrasebook" && e.src == .en {
            guard let p = byText[e.text], seen.insert(p.en).inserted else { continue }
            out.append(p)
            if out.count == limit { break }
        }
        return out
    }
}
