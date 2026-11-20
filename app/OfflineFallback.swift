// OfflineFallback.swift – Satzbuch-Fallback ohne Netz und ohne Übersetzer: findet zu einem Text den ähnlichsten Satz im
// Satzbuch (Szenario-Pakete + eigene Sätze) und liefert dessen Gegenstück. Ähnlichkeit = Dice-Koeffizient über
// Zeichen-Bigramme (funktioniert auch für Thai ohne Wortgrenzen). Nur Foundation; getestet in swift-tests.
import Foundation

struct BookPhrase: Equatable {
    var en: String
    var th: String
    var critical = false
}

struct BookMatch: Equatable {
    var phrase: BookPhrase
    var score: Double
    var inputIsThai: Bool
    /// Der Satz in der anderen Sprache (das, was man sagt oder zeigt).
    var answer: String { inputIsThai ? phrase.en : phrase.th }
}

enum OfflineFallback {
    /// Mindestähnlichkeit; darunter wird lieber nichts angeboten als ein falscher Satz.
    static let threshold = 0.62

    static func normalize(_ s: String) -> String { UtteranceLogic.normalize(s) }

    static func isThai(_ s: String) -> Bool {
        let thai = s.unicodeScalars.filter { (0x0E00...0x0E7F).contains($0.value) }.count
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letters > 0 && thai * 2 >= letters
    }

    static func bigrams(_ s: String) -> [String: Int] {
        let c = Array(normalize(s))
        guard c.count >= 2 else { return c.isEmpty ? [:] : [String(c): 1] }
        var m: [String: Int] = [:]
        for i in 0..<(c.count - 1) { m[String([c[i], c[i + 1]]), default: 0] += 1 }
        return m
    }

    static func dice(_ a: String, _ b: String) -> Double {
        let x = bigrams(a), y = bigrams(b)
        let nx = x.values.reduce(0, +), ny = y.values.reduce(0, +)
        guard nx > 0, ny > 0 else { return 0 }
        var common = 0
        for (k, v) in x { common += min(v, y[k] ?? 0) }
        return 2 * Double(common) / Double(nx + ny)
    }

    /// Bester Treffer ab `threshold`; bei Gleichstand gewinnt ein kritischer Satz, dann der kürzere.
    static func match(_ input: String, in book: [BookPhrase], threshold: Double = threshold) -> BookMatch? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalize(t).count >= 2 else { return nil }
        let thai = isThai(t)
        var best: BookMatch?
        for p in book {
            let ref = thai ? p.th : p.en
            let s = dice(t, ref)
            guard s >= threshold else { continue }
            let m = BookMatch(phrase: p, score: s, inputIsThai: thai)
            guard let b = best else { best = m; continue }
            if s > b.score + 0.001 { best = m; continue }
            guard abs(s - b.score) <= 0.001 else { continue }
            let bRef = thai ? b.phrase.th : b.phrase.en
            if p.critical != b.phrase.critical {
                if p.critical { best = m }
            } else if ref.count < bRef.count {
                best = m
            }
        }
        return best
    }

    /// Mehrere Vorschläge (absteigend), z. B. für eine Liste „Meinten Sie …“.
    static func suggestions(_ input: String, in book: [BookPhrase], limit: Int = 3, threshold: Double = 0.45) -> [BookMatch] {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalize(t).count >= 2 else { return [] }
        let thai = isThai(t)
        var all: [BookMatch] = []
        for p in book {
            let sc = dice(t, thai ? p.th : p.en)
            if sc >= threshold { all.append(BookMatch(phrase: p, score: sc, inputIsThai: thai)) }
        }
        all.sort { (x: BookMatch, y: BookMatch) -> Bool in
            if x.score != y.score { return x.score > y.score }
            return x.phrase.en < y.phrase.en
        }
        return Array(all.prefix(max(0, limit)))
    }
}
