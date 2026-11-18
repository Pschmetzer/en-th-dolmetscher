// HistoryLogic.swift – Runde 18: Verlauf durchsuchen, filtern, nach Tag gruppieren, Auswahl und Aufbewahrungshinweis.
// Reine Logik ohne UI und Modell (Favoriten kommen als Closure), damit XCTest sie ohne App prüft.
import Foundation

/// Zeitraum-Filter des Verlaufs.
enum HistoryRange: String, CaseIterable, Sendable {
    case all, today, week, month

    var textKey: String { "hs_range_" + rawValue }

    /// Frühester erlaubter Zeitpunkt (Tagesbeginn); nil = ohne Grenze. „Woche“ = die letzten 7 Tage samt heute.
    func start(now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .all: return nil
        case .today: return today
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        }
    }
}

/// Sprachpaar ohne Richtung: en→th und th→en gehören zusammen.
struct HistoryPair: Hashable, Sendable {
    let first: Lang
    let second: Lang

    init(_ a: Lang, _ b: Lang) {
        let sorted = a.rawValue <= b.rawValue
        first = sorted ? a : b
        second = sorted ? b : a
    }

    init(_ e: Entry) { self.init(e.src, e.target) }
}

struct HistoryFilter: Equatable {
    var query = ""
    var pair: HistoryPair?
    var range: HistoryRange = .all
    var favoritesOnly = false

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isActive: Bool { !trimmedQuery.isEmpty || pair != nil || range != .all || favoritesOnly }
    /// Zahl der gesetzten Filter ohne die Suche (Abzeichen am Filtermenü).
    var activeCount: Int { (pair != nil ? 1 : 0) + (range != .all ? 1 : 0) + (favoritesOnly ? 1 : 0) }
}

struct HistoryDay: Identifiable, Equatable {
    let day: Date
    let entries: [Entry]
    var id: Date { day }
}

enum HistoryDayLabel: Equatable {
    case today, yesterday, date(Date)
}

enum HistoryEmpty: Equatable {
    case none, nothingSaved, noMatches
}

enum HistoryLogic {
    /// Treffer: Suche in Satz und Übersetzung (Groß-/Kleinschreibung und Akzente egal) plus alle gesetzten Filter.
    static func apply(_ f: HistoryFilter, to entries: [Entry], isFavorite: (Entry) -> Bool,
                      now: Date = Date(), calendar: Calendar = .current) -> [Entry] {
        let q = f.trimmedQuery
        let from = f.range.start(now: now, calendar: calendar)
        return entries.filter { e in
            if let from, e.date < from { return false }
            if let p = f.pair, HistoryPair(e) != p { return false }
            if f.favoritesOnly, !isFavorite(e) { return false }
            return q.isEmpty || matches(e, q)
        }
    }

    private static func matches(_ e: Entry, _ q: String) -> Bool {
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return e.text.range(of: q, options: opts) != nil || e.translation?.range(of: q, options: opts) != nil
    }

    /// Sprachpaare, die im Verlauf vorkommen – das häufigste zuerst.
    static func pairs(in entries: [Entry]) -> [HistoryPair] {
        var count: [HistoryPair: Int] = [:]
        for e in entries { count[HistoryPair(e), default: 0] += 1 }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.first.rawValue < $1.key.first.rawValue }.map(\.key)
    }

    /// Nach Kalendertag gruppiert: neuester Tag zuerst, innerhalb eines Tages in Gesprächsreihenfolge.
    static func groups(_ entries: [Entry], calendar: Calendar = .current) -> [HistoryDay] {
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { day in
            HistoryDay(day: day, entries: byDay[day, default: []].sorted { $0.date < $1.date })
        }
    }

    static func label(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> HistoryDayLabel {
        if calendar.isDate(day, inSameDayAs: now) { return .today }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: y) { return .yesterday }
        return .date(day)
    }

    static func empty(total: Int, shown: Int) -> HistoryEmpty {
        if total == 0 { return .nothingSaved }
        return shown == 0 ? .noMatches : .none
    }

    /// Hinweis zur Aufbewahrung (`historyDays`: 0 nichts, 1 Tag, n Tage, <0 für immer): Textschlüssel und Zahl.
    static func retention(days: Int) -> (key: String, count: Int?) {
        switch days {
        case 0: return ("hs_keep_none", nil)
        case 1: return ("hs_keep_1", nil)
        case ..<0: return ("hs_keep_forever", nil)
        default: return ("hs_keep_days", days)
        }
    }

    /// Ausgewählte Einträge in Verlaufsreihenfolge; ids, die es nicht mehr gibt, fallen weg.
    static func selected(_ entries: [Entry], ids: Set<UUID>) -> [Entry] {
        entries.filter { ids.contains($0.id) }
    }

    /// Alles Sichtbare an- oder abwählen: sind schon alle gewählt, wird die Auswahl leer.
    static func toggleAll(visible: [Entry], selection: Set<UUID>) -> Set<UUID> {
        let all = Set(visible.map(\.id))
        return !all.isEmpty && all.isSubset(of: selection) ? selection.subtracting(all) : selection.union(all)
    }
}
