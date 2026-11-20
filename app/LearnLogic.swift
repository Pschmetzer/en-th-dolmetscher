// LearnLogic.swift – Lern-Modus: Satz Wort für Wort zerlegen (auch Thai ohne Leerzeichen), Lückentext und Anki-Karten
// direkt aus ausgewählten Blasen (ohne Umweg über den Verlauf). Nur Foundation; getestet in swift-tests.
import Foundation

enum LearnLogic {
    /// Wörter eines Satzes in Reihenfolge. Nutzt die Wortgrenzen des Systems (ICU), damit auch Thai getrennt wird;
    /// Satzzeichen und Leerzeichen fallen weg.
    static func words(_ text: String) -> [String] { wordRanges(text).map { String(text[$0]) } }

    /// Wortbereiche im Text (gleiche Regeln wie `words`): so trifft die Lücke genau das gewählte Wort.
    static func wordRanges(_ text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { w, r, _, _ in
            if let w, w.contains(where: { $0.isLetter || $0.isNumber }) { out.append(r) }
        }
        return out
    }

    /// Wörter mit Position – für „Wort antippen → Glossar / Wörterbuch“.
    struct Token: Equatable { var word: String; var index: Int }

    static func tokens(_ text: String) -> [Token] { words(text).enumerated().map { Token(word: $1, index: $0) } }

    /// Lückentext: das Wort an `index` wird durch „____“ (Länge ~ Wortlänge, 3…8) ersetzt. nil bei ungültigem Index
    /// oder wenn der Satz weniger als zwei Wörter hat.
    static func cloze(_ text: String, hiding index: Int) -> (prompt: String, answer: String)? {
        let ranges = wordRanges(text)
        guard ranges.count >= 2, ranges.indices.contains(index) else { return nil }
        let answer = String(text[ranges[index]])
        var p = text
        p.replaceSubrange(ranges[index], with: String(repeating: "_", count: min(8, max(3, answer.count))))
        return (p, answer)
    }

    /// Wähle ein sinnvolles Lückenwort: das längste Wort (Ties: das spätere) – meist ein Inhaltswort, kein „the“.
    static func defaultClozeIndex(_ text: String) -> Int? {
        let toks = words(text)
        guard toks.count >= 2 else { return nil }
        var best = 0
        for (i, w) in toks.enumerated() where w.count >= toks[best].count { best = i }
        return best
    }

    // MARK: Anki aus Blasen

    struct Card: Equatable { var front: String; var back: String; var tag: String }

    /// Karten aus Äußerungen: Vorderseite = Satz in `frontLang` (sonst die Übersetzung, wenn sie in dieser Sprache ist),
    /// Rückseite = die andere Seite. Ohne Übersetzung und doppelte Vorderseiten werden übersprungen.
    static func cards(_ items: [ExportItem], frontLang: String?) -> [Card] {
        var seen = Set<String>(), out: [Card] = []
        for u in items {
            let a = u.text.trimmingCharacters(in: .whitespacesAndNewlines), b = u.out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard u.translated, !a.isEmpty, !b.isEmpty else { continue }
            var front = a, back = b, lang = u.lang
            if let fl = frontLang, !fl.isEmpty {
                if u.lang == fl { /* passt */ } else if u.to == fl { front = b; back = a; lang = u.to } else { continue }
            }
            guard seen.insert(front.lowercased()).inserted else { continue }
            out.append(Card(front: front, back: back, tag: "dolmetscher " + (lang.isEmpty ? "xx" : lang)))
        }
        return out
    }

    /// Anki-Import (CSV mit Kopfzeilen wie in der Verlaufs-Ausgabe).
    static func ankiCSV(_ cards: [Card]) -> String {
        var out = "#separator:comma\n#html:true\n#columns:Front,Back,Tags\n#tags column:3\n"
        for c in cards {
            out += [R23History.ankiField(c.front), R23History.ankiField(c.back), R23History.ankiField(c.tag)].joined(separator: ",") + "\n"
        }
        return out
    }
}
