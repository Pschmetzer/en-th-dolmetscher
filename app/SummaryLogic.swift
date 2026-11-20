// SummaryLogic.swift – Zusammenfassung eines Gesprächs aus dem Verlauf, rein lokal (kein Netz, kein Modell):
// Eckdaten, offene Fragen, Preise, Zahlen und mögliche To-dos (Stichwort-Erkennung in de/en/th) mit Markdown-Export.
// Nur Foundation; getestet in swift-tests.
import Foundation

struct ConversationSummary: Equatable {
    var turns = 0
    var minutes = 0
    var languages: [String: Int] = [:]
    var questions: [String] = []
    var todos: [String] = []
    var prices: [PriceMention] = []
    var numbers: [String] = []
}

enum SummaryLogic {
    /// Stichwörter, die auf eine Aufgabe, Verabredung oder Bitte hindeuten (klein geschrieben verglichen).
    static let todoMarkers: [String] = [
        "i need to", "we need to", "you need to", "don't forget", "remember to", "please bring", "please send", "please call",
        "i will", "i'll", "we will", "tomorrow", "pick up", "meet at", "be there at", "deadline", "must ",
        "ich muss", "wir müssen", "du musst", "nicht vergessen", "bitte bring", "bitte schick", "bitte ruf", "morgen", "abholen", "treffen um",
        "ต้อง", "อย่าลืม", "พรุ่งนี้", "ช่วย", "นัด", "รับ", "เจอกัน",
    ]

    /// Sätze eines Textes (Satzzeichen . ! ? 。 und Zeilenumbruch (nicht der Punkt in Zahlen wie 10.30)), getrimmt, ohne Leeres.
    static func sentences(_ text: String) -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            cur.append(ch)
            // Punkt zwischen zwei Ziffern (3.5, 10.30, ฿1.200) ist kein Satzende
            if ch == ".", i > 0, i + 1 < chars.count, chars[i - 1].isNumber, chars[i + 1].isNumber { continue }
            if ".!?\n。！？".contains(ch) { out.append(cur); cur = "" }
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func isQuestion(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("?") || t.hasSuffix("？") { return true }
        // Thai hat kein Fragezeichen: typische Fragepartikel am Satzende
        return ["ไหม", "มั้ย", "หรือเปล่า", "หรือไม่", "เท่าไร", "เท่าไหร่", "ที่ไหน", "ไหมครับ", "ไหมคะ"].contains { t.hasSuffix($0) }
    }

    static func isTodo(_ s: String) -> Bool {
        let l = s.lowercased()
        return !isQuestion(s) && todoMarkers.contains { l.contains($0) }
    }

    /// Doppelte (ohne Groß/Klein und Satzzeichen) nur einmal, Reihenfolge bleibt.
    static func unique(_ list: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for s in list where seen.insert(UtteranceLogic.normalize(s)).inserted { out.append(s) }
        return out
    }

    static func summarize(_ items: [ExportItem], limit: Int = 12) -> ConversationSummary {
        var s = ConversationSummary()
        let done = items.filter { !$0.text.isEmpty }
        s.turns = done.count
        if let a = done.first?.at, let b = done.last?.at { s.minutes = max(0, Int((b.timeIntervalSince(a) / 60).rounded())) }
        var qs: [String] = [], ts: [String] = [], ps: [PriceMention] = [], ns: [String] = []
        for u in done {
            s.languages[u.lang, default: 0] += 1
            for sent in sentences(u.text) {
                if isQuestion(sent) { qs.append(sent) } else if isTodo(sent) { ts.append(sent) }
            }
            // Preise stehen im Original oder in der Übersetzung; gleiche Beträge nicht doppelt führen
            for m in PriceLogic.mentions(in: u.text) + PriceLogic.mentions(in: u.out)
            where !ps.contains(where: { $0.amount == m.amount && $0.currency == m.currency }) { ps.append(m) }
            ns += NumberWarning.numbers(in: u.text)
        }
        s.questions = Array(unique(qs).prefix(limit))
        s.todos = Array(unique(ts).prefix(limit))
        s.prices = Array(ps.prefix(limit))
        let priceAmounts = Set(ps.map(\.amount))
        s.numbers = Array(unique(ns).filter { n in
            n.count >= 2 && !(PriceLogic.parseAmount(n).map { priceAmounts.contains($0) } ?? false)
        }.prefix(limit))
        return s
    }

    /// Markdown für Notizen oder Mail. `labels` = Überschriften in der Oberflächensprache (Schlüssel siehe Test).
    static func markdown(_ s: ConversationSummary, title: String, labels: [String: String], rate: Double? = nil,
                         comma: Bool = true) -> String {
        func l(_ k: String) -> String { labels[k] ?? k }
        var o = "# \(ExportFormats.mdEscape(title))\n\n"
        let langs = s.languages.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { "\($0.key.uppercased()) \($0.value)" }.joined(separator: ", ")
        o += "\(l("turns")): \(s.turns) · \(l("minutes")): \(s.minutes)" + (langs.isEmpty ? "" : " · \(langs)") + "\n"
        func section(_ key: String, _ lines: [String], bullet: String = "- ") {
            guard !lines.isEmpty else { return }
            o += "\n## \(l(key))\n\n" + lines.map { bullet + ExportFormats.mdEscape($0) }.joined(separator: "\n") + "\n"
        }
        section("todos", s.todos, bullet: "- [ ] ")
        section("questions", s.questions)
        section("prices", s.prices.map { PriceLogic.conversionLine($0, rate: rate, comma: comma) ?? $0.raw })
        section("numbers", s.numbers)
        return o
    }

    /// Reiner Text (Zwischenablage, Mitteilung): eine Zeile je Punkt, Abschnitte mit Überschrift.
    static func plain(_ s: ConversationSummary, labels: [String: String]) -> String {
        func l(_ k: String) -> String { labels[k] ?? k }
        var parts: [String] = []
        for (k, v) in [("todos", s.todos), ("questions", s.questions), ("prices", s.prices.map(\.raw)), ("numbers", s.numbers)] where !v.isEmpty {
            parts.append(l(k) + ":\n" + v.map { "• " + $0 }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}
