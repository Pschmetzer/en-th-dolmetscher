// ScenarioDetect.swift – erkennt aus den letzten Sätzen, welches Szenario-Paket passt (Taxi, Arzt, Markt …), und
// schlägt es als Quick-Phrasen-Set vor. Rein lokal: Stichwörter je Paket (presets-index.json `keywords`) werden in den
// letzten Äußerungen gezählt. Nur Foundation; getestet in swift-tests.
import Foundation

struct ScenarioCandidate: Equatable {
    var id: String
    var keywords: [String]
}

struct ScenarioSuggestion: Equatable {
    var id: String
    var score: Int
    var matched: [String]
}

enum ScenarioDetect {
    /// So viele letzte Äußerungen zählen.
    static let window = 6
    /// So viele verschiedene Stichwörter braucht ein Vorschlag mindestens.
    static let minDistinct = 2

    /// Stichwort kommt als ganzes Wort (lateinisch) bzw. als Teilfolge (Thai, kein Leerzeichen) im Text vor.
    static func contains(_ haystack: String, keyword: String) -> Bool {
        let h = haystack.lowercased(), k = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard k.count >= 3 else { return false }
        if k.unicodeScalars.contains(where: { (0x0E00...0x0E7F).contains($0.value) }) { return h.contains(k) }
        var from = h.startIndex
        while let r = h.range(of: k, range: from..<h.endIndex) {
            let beforeOK = r.lowerBound == h.startIndex || !h[h.index(before: r.lowerBound)].isLetter
            // Endungen wie „s“/„es“ (taxis, pharmacies) zulassen: danach darf höchstens ein kurzer Wortrest folgen
            var end = r.upperBound, tail = 0
            while end < h.endIndex, h[end].isLetter, tail < 3 { end = h.index(after: end); tail += 1 }
            let afterOK = end == h.endIndex || !h[end].isLetter
            if beforeOK && afterOK { return true }
            from = r.upperBound
        }
        return false
    }

    /// Bester Treffer in den letzten `window` Texten. Nur Pakete mit ≥ `minDistinct` verschiedenen Stichwörtern.
    /// `exclude` = schon aktives oder weggeklicktes Paket.
    static func suggest(recent: [String], candidates: [ScenarioCandidate], exclude: Set<String> = []) -> ScenarioSuggestion? {
        let text = recent.suffix(window).joined(separator: " \n ")
        guard !text.isEmpty else { return nil }
        var best: ScenarioSuggestion?
        for c in candidates where !exclude.contains(c.id) {
            let hits = Array(Set(c.keywords.map { $0.lowercased() })).filter { contains(text, keyword: $0) }.sorted()
            guard hits.count >= minDistinct else { continue }
            let s = ScenarioSuggestion(id: c.id, score: hits.count, matched: hits)
            if best == nil || s.score > best!.score || (s.score == best!.score && s.id < best!.id) { best = s }
        }
        return best
    }

    /// Vorschlag erst zeigen, wenn er in zwei Prüfungen hintereinander derselbe war (kein Flackern bei Nebenbemerkungen).
    static func stable(previous: String?, current: ScenarioSuggestion?) -> ScenarioSuggestion? {
        guard let current, previous == current.id else { return nil }
        return current
    }

    /// Stichwörter je Paket aus den englischen Sätzen ableiten (die App-Presets tragen keine `keywords`): Wörter ab 5
    /// Buchstaben, die in höchstens `maxPacks` Paketen vorkommen (häufige Wörter sind keine Merkmale), je Paket die
    /// `perPack` häufigsten.
    static func deriveCandidates(packs: [(id: String, phrases: [String])], maxPacks: Int = 3, perPack: Int = 12) -> [ScenarioCandidate] {
        func tokens(_ s: String) -> [String] {
            s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 5 && !$0.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) } }
        }
        var packWords: [String: [String: Int]] = [:]
        var df: [String: Int] = [:]
        for p in packs {
            var counts: [String: Int] = [:]
            for ph in p.phrases { for w in tokens(ph) { counts[w, default: 0] += 1 } }
            packWords[p.id] = counts
            for w in counts.keys { df[w, default: 0] += 1 }
        }
        return packs.map { p in
            var words: [(key: String, value: Int)] = []
            for (w, n) in packWords[p.id] ?? [:] where (df[w] ?? 0) <= maxPacks { words.append((w, n)) }
            words.sort { (x: (key: String, value: Int), y: (key: String, value: Int)) -> Bool in
                x.value != y.value ? x.value > y.value : x.key < y.key
            }
            return ScenarioCandidate(id: p.id, keywords: words.prefix(perPack).map { $0.key })
        }
    }
}
