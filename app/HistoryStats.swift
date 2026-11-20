// HistoryStats.swift – Auswertung des geladenen Verlaufs (reine Logik, Foundation + HistoryLogic).
import Foundation

struct HistoryStatsResult: Equatable {
    var utterances = 0
    var sessions = 0
    var words = 0
    /// Letzte bis zu 7 Tage mit Äußerungen, älteste zuerst: (yyyy-MM-dd, Anzahl).
    var perDay: [(String, Int)] = []
    var top: [(String, Int)] = []

    static func == (a: HistoryStatsResult, b: HistoryStatsResult) -> Bool {
        a.utterances == b.utterances && a.sessions == b.sessions && a.words == b.words
            && a.perDay.map { $0.0 + String($0.1) } == b.perDay.map { $0.0 + String($0.1) }
            && a.top.map { $0.0 + String($0.1) } == b.top.map { $0.0 + String($0.1) }
    }
}

extension HistoryLogic {
    static func stats(_ sessions: [HistorySession], timeZone: TimeZone = .current, top n: Int = 5) -> HistoryStatsResult {
        var r = HistoryStatsResult()
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        var days: [String: Int] = [:]
        var counts: [String: (Int, String)] = [:]
        for s in sessions where !s.rows.isEmpty {
            r.sessions += 1
            for row in s.rows {
                r.utterances += 1
                r.words += row.text.split(whereSeparator: { $0.isWhitespace }).count
                let c = cal.dateComponents([.year, .month, .day], from: row.time)
                days[String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0), default: 0] += 1
                let flat = row.text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                let key = flat.lowercased()
                if !key.isEmpty { counts[key, default: (0, flat)].0 += 1 }
            }
        }
        r.perDay = days.keys.sorted().suffix(7).map { ($0, days[$0] ?? 0) }
        r.top = counts.values.filter { $0.0 > 1 }.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .prefix(n).map { ($0.1, $0.0) }
        return r
    }
}
