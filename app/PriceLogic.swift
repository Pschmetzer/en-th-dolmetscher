// PriceLogic.swift – Preise und Zahlen im Gespräch erkennen, THB ↔ EUR mit manuellem Kurs umrechnen, „Zahl groß zeigen“
// und Verhandlungs-Vorschläge (reine Logik, nur Foundation; getestet in swift-tests). Kein Online-Kurs: der Kurs ist
// eine Eingabe des Nutzers (Baht pro Euro).
import Foundation

enum Money: String, Equatable { case thb, eur }

struct PriceMention: Equatable {
    var amount: Double
    var currency: Money?     // nil = nur eine Zahl ohne Währung
    var raw: String          // so im Text gefunden
}

enum PriceLogic {
    /// Kurs-Eingabe („36,5“ / „36.5“ / „ 38 “) → Baht pro Euro; nil wenn unbrauchbar (≤ 0, > 1000, keine Zahl).
    static func parseRate(_ s: String) -> Double? {
        guard let v = parseAmount(s.trimmingCharacters(in: .whitespacesAndNewlines)), v > 0, v <= 1000 else { return nil }
        return v
    }

    /// Thai-Ziffern → arabische Ziffern.
    static func westernDigits(_ s: String) -> String {
        String(s.map { ch -> Character in
            if let v = ch.unicodeScalars.first?.value, (0x0E50...0x0E59).contains(v), let u = UnicodeScalar(v - 0x0E50 + 0x30) {
                return Character(u)
            }
            return ch
        })
    }

    /// Zahl mit Tausender-/Dezimaltrennzeichen lesen: „1,200“ „1.200,50“ „1 200“ „12.5“ „12,50“ „๑๒๐“.
    /// Genau drei Stellen nach einem einzelnen Trenner gelten als Tausender („12.500“), sonst als Dezimalstellen.
    static func parseAmount(_ raw: String) -> Double? {
        var s = westernDigits(raw).replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber || ",. ".contains($0) }), s.contains(where: \.isNumber) else { return nil }
        s = s.replacingOccurrences(of: " ", with: "")
        var decimalSep: Character?
        switch (s.lastIndex(of: ","), s.lastIndex(of: ".")) {
        case let (c?, d?): decimalSep = c > d ? "," : "."
        case let (c?, nil): decimalSep = s[s.index(after: c)...].count == 3 && !s.hasPrefix("0,") ? nil : ","
        case let (nil, d?): decimalSep = s[s.index(after: d)...].count == 3 && !s.hasPrefix("0.") ? nil : "."
        default: decimalSep = nil
        }
        var intPart = s, frac = ""
        if let sep = decimalSep, let i = s.lastIndex(of: sep) {
            intPart = String(s[..<i]); frac = String(s[s.index(after: i)...])
        }
        intPart = intPart.filter(\.isNumber); frac = frac.filter(\.isNumber)
        guard !intPart.isEmpty || !frac.isEmpty else { return nil }
        return Double((intPart.isEmpty ? "0" : intPart) + (frac.isEmpty ? "" : "." + frac))
    }

    private static let number = "[0-9๐-๙]+(?:[.,\\s][0-9๐-๙]{3})*(?:[.,][0-9๐-๙]{1,2})?"
    private static let thbWords = "฿|THB|Baht|baht|BAHT|บาท"
    private static let eurWords = "€|EUR|Euros?|euros?"
    private static let before = try! NSRegularExpression(pattern: "(\(thbWords)|\(eurWords))\\s?(\(number))")
    private static let after = try! NSRegularExpression(pattern: "(\(number))\\s?(\(thbWords)|\(eurWords))(?![A-Za-zก-๙])")
    private static let bare = try! NSRegularExpression(pattern: "(?<![0-9๐-๙.,])(\(number))(?![0-9๐-๙])")

    private static func currency(_ word: String) -> Money? {
        let w = word.lowercased()
        if ["฿", "thb", "baht", "บาท"].contains(w) { return .thb }
        if ["€", "eur", "euro", "euros"].contains(w) { return .eur }
        return nil
    }

    /// Alle Beträge im Text, in Textreihenfolge. Zahlen ohne Währungswort nur mit `includeBare` (und ab `bareMin`).
    static func mentions(in text: String, includeBare: Bool = false, bareMin: Double = 20) -> [PriceMention] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        typealias Hit = (loc: Int, len: Int, m: PriceMention)
        var found: [Hit] = []
        for (re, wordFirst) in [(before, true), (after, false)] {
            re.enumerateMatches(in: text, range: full) { m, _, _ in
                guard let m else { return }
                let w = ns.substring(with: m.range(at: wordFirst ? 1 : 2)), n = ns.substring(with: m.range(at: wordFirst ? 2 : 1))
                guard let cur = currency(w), let a = parseAmount(n) else { return }
                found.append((m.range.location, m.range.length, PriceMention(amount: a, currency: cur, raw: ns.substring(with: m.range))))
            }
        }
        // Überlappungen (dieselbe Zahl von beiden Mustern) entfernen: der früher beginnende, längere Treffer gewinnt.
        found.sort { $0.loc < $1.loc || ($0.loc == $1.loc && $0.len > $1.len) }
        var kept: [Hit] = []
        for f in found where !kept.contains(where: { f.loc < $0.loc + $0.len && $0.loc < f.loc + f.len }) { kept.append(f) }
        if includeBare {
            bare.enumerateMatches(in: text, range: full) { m, _, _ in
                guard let m, !kept.contains(where: { m.range.location < $0.loc + $0.len && $0.loc < m.range.location + m.range.length }),
                      let a = parseAmount(ns.substring(with: m.range(at: 1))), a >= bareMin else { return }
                kept.append((m.range.location, m.range.length, PriceMention(amount: a, currency: nil, raw: ns.substring(with: m.range))))
            }
            kept.sort { $0.loc < $1.loc }
        }
        return kept.map(\.m)
    }

    /// `rate` = Baht pro Euro.
    static func convert(_ amount: Double, from: Money, rate: Double) -> Double {
        guard rate > 0 else { return amount }
        return from == .thb ? amount / rate : amount * rate
    }

    static func other(_ c: Money) -> Money { c == .thb ? .eur : .thb }

    /// „1.200 ฿“ / „12,50 €“; Baht ganzzahlig, Euro mit zwei Stellen (nur bei Rest). Trennzeichen nach `comma` (de: Komma).
    static func format(_ amount: Double, _ c: Money, comma: Bool = true) -> String {
        let v = c == .thb ? amount.rounded() : (amount * 100).rounded() / 100   // erst auf Cent runden: 12,995 → 13,00 nicht „12,99/13.00“
        let whole = abs(v - v.rounded()) < 0.005
        let body = whole ? String(Int(v.rounded())) : String(format: "%.2f", v)
        var intPart = body, frac = ""
        if let dot = body.firstIndex(of: ".") { intPart = String(body[..<dot]); frac = String(body[body.index(after: dot)...]) }
        var grouped = ""
        for (i, ch) in intPart.reversed().enumerated() {
            if i > 0, i % 3 == 0 { grouped.append(comma ? "." : ",") }
            grouped.append(ch)
        }
        return String(grouped.reversed()) + (frac.isEmpty ? "" : (comma ? "," : ".") + frac) + (c == .thb ? " ฿" : " €")
    }

    /// Zeile „Preis ≈ Umrechnung“ für eine Erwähnung; nil ohne Währung oder ohne Kurs.
    static func conversionLine(_ m: PriceMention, rate: Double?, comma: Bool = true) -> String? {
        guard let c = m.currency, let rate else { return nil }
        return format(m.amount, c, comma: comma) + " ≈ " + format(convert(m.amount, from: c, rate: rate), other(c), comma: comma)
    }

    // MARK: Verhandlung

    struct Offer: Equatable { var percent: Int; var amount: Double }

    private static func step(for price: Double) -> Double { price >= 200 ? 10 : (price >= 50 ? 5 : 1) }

    /// Gegenangebote in Stufen vom verlangten Preis (Standard 70 %, 80 %, 90 %), auf glatte Beträge gerundet.
    static func counterOffers(asking: Double, percents: [Int] = [70, 80, 90]) -> [Offer] {
        guard asking > 0 else { return [] }
        let st = step(for: asking)
        return percents.filter { (1...99).contains($0) }.map { p in
            Offer(percent: p, amount: max(st, (asking * Double(p) / 100 / st).rounded() * st))
        }
    }

    /// Nächstes Gebot beim Feilschen: ich bin bei `mine`, das Gegenüber bei `theirs`; Vorschlag liegt dazwischen
    /// (40 % des Abstands), nie über dem Budget. nil, wenn kein Spielraum bleibt.
    static func nextBid(mine: Double, theirs: Double, maxBudget: Double? = nil) -> Double? {
        guard mine > 0, theirs > mine else { return nil }
        var bid = mine + (theirs - mine) * 0.4
        if let cap = maxBudget { bid = min(bid, cap) }
        let st = step(for: theirs)
        let r = (bid / st).rounded() * st
        return r > mine && r < theirs ? r : nil
    }
}
