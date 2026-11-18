// ShortcutLogic.swift – reine Logik der Kurzbefehle der Runde 17 (kein UI, kein Netz, testbar ohne Simulator-Sprachausgabe).
import Foundation

/// „Sprachpaar wechseln“: tauscht meine Sprache und die des Partners.
enum PairSwitch {
    static func swapped(_ pair: LangPair) -> LangPair { LangPair(mine: pair.partner, partner: pair.mine) }
}

/// „Letzte Übersetzung vorlesen“: der jüngste Eintrag, der schon eine Übersetzung hat.
enum LastSpeech {
    static func pick(_ entries: [Entry]) -> Entry? {
        entries.last { ($0.translation ?? "").trimmingCharacters(in: .whitespaces).isEmpty == false }
    }
}

/// „Satz aus dem Satzbuch sagen“: findet zu einem gesprochenen oder getippten Suchwort den besten Satz.
enum PhraseMatcher {
    /// Ohne Groß-/Kleinschreibung und Akzente, ohne Satzzeichen und Mehrfach-Leerraum.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        return words.joined(separator: " ")
    }

    /// 3 = genau, 2 = Satz beginnt damit, 1 = kommt vor, 0 = kein Treffer. Englisch und deutsche Glosse zählen.
    static func score(_ query: String, _ p: Phrase) -> Int {
        let q = normalize(query)
        guard !q.isEmpty else { return 0 }
        return [p.en, p.de ?? ""].map { text -> Int in
            let t = normalize(text)
            if t == q { return 3 }
            if t.hasPrefix(q) { return 2 }
            return t.contains(q) ? 1 : 0
        }.max() ?? 0
    }

    /// Bester Treffer; bei Gleichstand der kürzere Satz (genauer getroffen), dann die frühere Stelle.
    static func best(_ query: String, in phrases: [Phrase]) -> Phrase? {
        phrases.enumerated()
            .map { (index: $0.offset, phrase: $0.element, score: score(query, $0.element)) }
            .filter { $0.score > 0 }
            .min { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.phrase.en.count != b.phrase.en.count { return a.phrase.en.count < b.phrase.en.count }
                return a.index < b.index
            }?.phrase
    }
}
