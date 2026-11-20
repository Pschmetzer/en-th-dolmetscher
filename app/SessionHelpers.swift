// SessionHelpers.swift – Namen aus dem Gespräch fürs Glossar, Satzbuch-Suche, Szenario-Vorschlag (reine Logik, Foundation).
import Foundation

enum NameSuggest {
    /// Großgeschriebene lateinische Wörter mitten im Satz (Namen/Orte), die noch nicht im Glossar stehen, häufigste zuerst.
    static func candidates(texts: [String], known: [String], limit: Int = 8) -> [String] {
        let knownSet = Set(known.map { $0.lowercased() })
        var counts: [String: (n: Int, shown: String)] = [:]
        for t in texts {
            var sentenceStart = true
            var word = ""
            func flush() {
                defer { word = "" }
                if word.hasSuffix("'s") { word.removeLast(2) }
                guard !word.isEmpty else { return }
                let first = word.first!
                if !sentenceStart, word.count >= 3, first.isUppercase, first.isLetter,
                   word.unicodeScalars.allSatisfy({ $0.value < 0x250 }),
                   word.dropFirst().contains(where: { $0.isLowercase }),
                   !knownSet.contains(word.lowercased()) {
                    counts[word.lowercased(), default: (0, word)].n += 1
                }
                sentenceStart = false
            }
            for ch in t {
                if ch.isLetter || ch == "'" && !word.isEmpty { word.append(ch) }
                else {
                    flush()
                    if ".!?\n".contains(ch) { sentenceStart = true }
                }
            }
            flush()
        }
        return counts.values.sorted { $0.n != $1.n ? $0.n > $1.n : $0.shown < $1.shown }.prefix(limit).map { $0.shown }
    }
}

struct PhraseSource {
    var id: String
    var name: String
    var phrases: [(en: String, th: String, critical: Bool)]
}

struct PhraseHit: Equatable, Identifiable {
    var presetID: String
    var presetName: String
    var en: String
    var th: String
    var critical: Bool
    var id: String { presetID + "|" + en + "|" + th }
}

enum PhraseSearch {
    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// Treffer in Englisch, Thai oder Szenario-Name; kritische Sätze zuerst. Leere Suche liefert nichts.
    static func search(_ sources: [PhraseSource], query: String, limit: Int = 80) -> [PhraseHit] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return [] }
        var hits: [PhraseHit] = []
        for s in sources {
            let nameMatch = fold(s.name).contains(q)
            for p in s.phrases where nameMatch || fold(p.en).contains(q) || fold(p.th).contains(q) {
                hits.append(PhraseHit(presetID: s.id, presetName: s.name, en: p.en, th: p.th, critical: p.critical))
            }
        }
        let sorted = hits.enumerated().sorted { a, b in
            a.element.critical != b.element.critical ? a.element.critical : a.offset < b.offset
        }.map { $0.element }
        return Array(sorted.prefix(limit))
    }
}

enum ScenarioSuggest {
    /// Bis zu drei Szenario-IDs passend zur Tageszeit (nur vorhandene).
    static func suggest(hour: Int, available: Set<String>) -> [String] {
        let ids: [String]
        switch hour {
        case 5..<11: ids = ["bakery-cafe", "hotel", "taxi"]
        case 11..<15: ids = ["restaurant", "street-food", "market"]
        case 15..<18: ids = ["shopping", "temple", "taxi"]
        case 18..<22: ids = ["street-food", "night-market-bargain", "restaurant"]
        default: ids = ["nightlife", "taxi", "hotel"]
        }
        return ids.filter { available.contains($0) }
    }
}
