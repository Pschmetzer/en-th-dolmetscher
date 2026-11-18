// Extras.swift – reine Logik für Runde 3: Umschrift, Rückübersetzungs-Vergleich, Bewertungsbitte, Thai-Zahlwörter.
// Ohne Geräte-APIs, unit-getestet (Round3Tests).
import Foundation

/// Umschrift (Lateinschrift) für Sprachen mit eigener Schrift – offline über ICU/CFStringTokenizer.
/// Nur eine Lesehilfe: bei Thai folgt sie der Schrift (ISO 11940, vereinfacht), nicht genau der Aussprache.
enum Romanizer {
    static let langs: Set<Lang> = [.th, .ja, .ko, .zh]

    static func latin(_ text: String, _ lang: Lang) -> String? {
        guard langs.contains(lang), lang.scriptShare(text) > 0.3 else { return nil }
        let out: String
        switch lang {
        case .ja:
            // Kanji über den Tokenizer (japanische Lesung) – `.toLatin` gäbe chinesisches Pinyin.
            out = tokens(text, locale: "ja").map { $0.latin ?? $0.word.applyingTransform(.toLatin, reverse: false) ?? $0.word }
                .joined(separator: " ")
        case .th:
            // Thai hat keine Leerzeichen zwischen Wörtern: erst trennen, dann je Wort umschreiben.
            out = tokens(text, locale: "th").map { thaiWord($0.word) }.joined(separator: " ")
        default:
            out = text.applyingTransform(.toLatin, reverse: false) ?? ""
        }
        let clean = tidy(out)
        return clean.isEmpty || clean == text ? nil : clean
    }

    /// ISO-11940-Zeichen lesbarer machen: Diakritika weg, อ (x) als o.
    static func thaiWord(_ w: String) -> String {
        guard Lang.th.scriptShare(w) > 0 else { return w }
        var s = w.applyingTransform(.toLatin, reverse: false) ?? w
        s = s.applyingTransform(.stripCombiningMarks, reverse: false) ?? s
        s = s.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) ?? s   // z. B. ı -> i
        return s.replacingOccurrences(of: "x", with: "o")
    }

    private static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "？", with: "?").replacingOccurrences(of: "！", with: "!")
        for p in [",", ".", "?", "!"] { t = t.replacingOccurrences(of: " " + p, with: p) }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokens(_ s: String, locale: String) -> [(word: String, latin: String?)] {
        let cf = s as CFString
        let tok = CFStringTokenizerCreate(nil, cf, CFRangeMake(0, CFStringGetLength(cf)),
                                          kCFStringTokenizerUnitWordBoundary, Locale(identifier: locale) as CFLocale)
        var out: [(String, String?)] = []
        var last = 0
        let ns = s as NSString
        while CFStringTokenizerAdvanceToNextToken(tok) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tok)
            // Satzzeichen zwischen den Wörtern behalten
            if r.location > last {
                let gap = ns.substring(with: NSRange(location: last, length: r.location - last)).trimmingCharacters(in: .whitespaces)
                if !gap.isEmpty { out.append((gap, gap)) }
            }
            let w = ns.substring(with: NSRange(location: r.location, length: r.length))
            out.append((w, CFStringTokenizerCopyCurrentTokenAttribute(tok, kCFStringTokenizerAttributeLatinTranscription) as? String))
            last = r.location + r.length
        }
        if last < ns.length {
            let tail = ns.substring(from: last).trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { out.append((tail, tail)) }
        }
        return out
    }
}

/// Rückübersetzung: weicht sie stark vom Original ab, ist die Übersetzung vermutlich falsch.
/// Zeichen-Bigramme (Dice) – funktioniert auch für Thai, Japanisch und Chinesisch ohne Leerzeichen.
enum BackCheck {
    /// Unter diesem Wert gilt die Rückübersetzung als „abweichend“.
    static let threshold = 0.45

    static func normalize(_ s: String) -> [Character] {
        Array(s.lowercased().folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber })
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let x = normalize(a), y = normalize(b)
        if x.isEmpty && y.isEmpty { return 1 }
        if x == y { return 1 }
        guard x.count > 1, y.count > 1 else { return x == y ? 1 : 0 }
        func grams(_ c: [Character]) -> [String: Int] {
            var g: [String: Int] = [:]
            for i in 0..<(c.count - 1) { g[String(c[i...i + 1]), default: 0] += 1 }
            return g
        }
        let gx = grams(x), gy = grams(y)
        let common = gx.reduce(0) { $0 + min($1.value, gy[$1.key] ?? 0) }
        return 2 * Double(common) / Double(x.count - 1 + y.count - 1)
    }

    /// Mindestlänge je Schrift: Ein chinesisches oder japanisches Zeichen trägt viel mehr als ein Buchstabe
    /// (8 Zeichen sind ein langer Satz), Thai liegt dazwischen.
    static func minLength(_ chars: [Character]) -> Int {
        var cjk = 0, thai = 0
        for c in chars {
            guard let v = c.unicodeScalars.first?.value else { continue }
            switch v {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF: cjk += 1
            case 0x0E00...0x0E7F: thai += 1
            default: break
            }
        }
        if cjk * 2 > chars.count { return 3 }
        if thai * 2 > chars.count { return 6 }
        return 8
    }

    /// Kurze Sätze („Ja“, „OK“) schwanken stark – dort nie warnen.
    static func deviates(original: String, back: String) -> Bool {
        let chars = normalize(original)
        guard chars.count >= minLength(chars) else { return false }
        return similarity(original, back) < threshold
    }
}

/// Bewertungsbitte: nach einigen erfolgreichen Gesprächen, nie mitten im Gespräch, höchstens einmal je Version.
struct ReviewGate: Equatable {
    static let neededConversations = 5
    /// Ein Gespräch zählt ab so vielen übersetzten Sätzen.
    static let minTranslations = 2

    var conversations = 0
    var askedVersion: String?

    mutating func conversationEnded(translations: Int) {
        if translations >= Self.minTranslations { conversations += 1 }
    }

    func shouldAsk(version: String, busy: Bool) -> Bool {
        !busy && conversations >= Self.neededConversations && askedVersion != version
    }

    mutating func asked(version: String) {
        askedVersion = version
        conversations = 0
    }

    static func load(_ d: UserDefaults) -> ReviewGate {
        ReviewGate(conversations: d.integer(forKey: "reviewConversations"), askedVersion: d.string(forKey: "reviewAskedVersion"))
    }

    func save(_ d: UserDefaults) {
        d.set(conversations, forKey: "reviewConversations")
        d.set(askedVersion, forKey: "reviewAskedVersion")
    }
}

/// Thai-Zahlwörter (สามร้อยห้าสิบ) – für Preise beim Handeln. 0 … 999 999 999.
enum ThaiNumber {
    private static let digits = ["ศูนย์", "หนึ่ง", "สอง", "สาม", "สี่", "ห้า", "หก", "เจ็ด", "แปด", "เก้า"]
    private static let places = ["", "สิบ", "ร้อย", "พัน", "หมื่น", "แสน"]

    static func words(_ n: Int) -> String? {
        guard n >= 0, n < 1_000_000_000 else { return nil }
        if n == 0 { return digits[0] }
        if n >= 1_000_000 {
            let rest = n % 1_000_000
            return words(n / 1_000_000)! + "ล้าน" + (rest > 0 ? below(rest, afterMillion: true) : "")
        }
        return below(n, afterMillion: false)
    }

    /// Bis 999 999. Regeln: 1 in der Zehnerstelle = สิบ (nicht หนึ่งสิบ), 2 dort = ยี่, 1 am Ende nach Zehnern = เอ็ด.
    private static func below(_ n: Int, afterMillion: Bool) -> String {
        let ds = String(n).compactMap { $0.wholeNumberValue }
        var out = ""
        for (i, d) in ds.enumerated() where d > 0 {
            let place = ds.count - 1 - i
            switch (place, d) {
            case (1, 1): out += "สิบ"
            case (1, 2): out += "ยี่สิบ"
            case (0, 1) where ds.count > 1 || afterMillion: out += "เอ็ด"
            default: out += digits[d] + places[place]
            }
        }
        return out
    }
}

/// Ziffern aus einer Eingabe (Antwortkarte „Zahl“) – höchstens 9 Stellen, führende Nullen weg.
enum NumberCard {
    /// Höchstens 9 Stellen, nach dem Dezimalpunkt höchstens 2 („12.50“ – Preise außerhalb Thailands).
    static func append(_ digit: Character, to s: String) -> String {
        if digit == "." {
            if s.contains(".") { return s }
            return s.isEmpty ? "0." : (s.count < 9 ? s + "." : s)
        }
        guard digit.isNumber, s.count < 9 else { return s }
        if let dot = s.firstIndex(of: ".") {
            return s[s.index(after: dot)...].count < 2 ? s + String(digit) : s
        }
        return s == "0" ? String(digit) : s + String(digit)
    }

    /// Anzeige mit Tausender- und Dezimaltrennzeichen der Zielsprache, bei ganzen Thai-Zahlen zusätzlich das Zahlwort.
    static func spoken(_ digits: String, in lang: Lang) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: lang.info.locale)
        if digits.contains(".") {
            let places = digits.split(separator: ".", omittingEmptySubsequences: false).last?.count ?? 0
            guard let v = Double(digits) else { return digits }
            f.minimumFractionDigits = places
            f.maximumFractionDigits = places
            var shown = f.string(from: NSNumber(value: v)) ?? digits
            // „5.“ (Punkt gerade getippt): das Trennzeichen mitzeigen.
            if places == 0 { shown += f.decimalSeparator ?? "." }
            return shown
        }
        guard let n = Int(digits) else { return digits }
        let shown = f.string(from: NSNumber(value: n)) ?? digits
        if lang == .th, let w = ThaiNumber.words(n) { return "\(shown) (\(w))" }
        return shown
    }
}
