// R28Logic.swift – kleine reine Logik der Runde 28 (nur Foundation; getestet in swift-tests/R28Tests.swift).
// Sprachparameter `lang` ist "de", "en" oder "th" (alles andere wie "en").
import Foundation

private func pick(_ lang: String, de: String, en: String, th: String) -> String {
    switch lang { case "de": return de; case "th": return th; default: return en }
}

/// 1. VoiceOver-Satz einer Blase: Sprecher, Original, Übersetzung, Uhrzeit.
enum BubbleA11y {
    static func label(speaker: String, original: String, translation: String, time: String?, lang: String) -> String {
        var parts: [String] = []
        let s = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { parts.append(s) }
        let o = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty { parts.append(o) }
        if !t.isEmpty { parts.append(pick(lang, de: "Übersetzung", en: "Translation", th: "คำแปล") + ": " + t) }
        if let tm = time, !tm.isEmpty { parts.append(tm) }
        return parts.joined(separator: ". ")
    }
}

/// 2. Einstellungen durchsuchen: mehrere Wörter (alle müssen vorkommen), ohne Groß-/Kleinschreibung und Akzente.
enum SettingsSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
    static func matches(haystack: String, query: String) -> Bool {
        let words = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return true }
        let h = fold(haystack)
        return words.allSatisfy { h.contains($0) }
    }
    static func filter<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
        items.filter { matches(haystack: text($0), query: query) }
    }
}

/// 3. Eigene globale Kürzel gegen von macOS belegte prüfen (Schreibweise wie `ShortcutCatalog`: ⌘ ⌥ ⇧ ⌃ + Taste).
enum SystemShortcutGuard {
    static let reserved: Set<String> = ["⌘Q", "⌘W", "⌘H", "⌥⌘H", "⌘M", "⌘⇥", "⌘␣", "⌃␣", "⌘,", "⌘C", "⌘V", "⌘X", "⌘Z", "⇧⌘Z",
                                         "⌘A", "⌘S", "⌘N", "⌘O", "⌘T", "⌥⌘␣", "⌃⌘Q", "⇧⌘3", "⇧⌘4", "⇧⌘5"]
    /// Reihenfolge der Modifikatoren normalisieren (⌃⌥⇧⌘), damit „⌘⇧3“ und „⇧⌘3“ gleich sind.
    static func normalize(_ keys: String) -> String {
        let order: [Character] = ["⌃", "⌥", "⇧", "⌘"]
        let mods = order.filter { keys.contains($0) }
        let rest = keys.filter { !order.contains($0) }.uppercased()
        return String(mods) + rest
    }
    static func isReserved(_ keys: String) -> Bool {
        let n = normalize(keys)
        return reserved.contains { normalize($0) == n }
    }
    /// Ein globales Kürzel ohne ⌘/⌃/⌥ würde normales Tippen abfangen.
    static func isSafeGlobal(_ keys: String) -> Bool {
        let n = normalize(keys)
        return (n.contains("⌘") || n.contains("⌃") || n.contains("⌥")) && n.count >= 2 && !isReserved(n)
    }
}

/// 4. Dauer der Sitzung: Uhr „1:05:03“ und gesprochen „1 Stunde 5 Minuten“.
enum SessionClock {
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
    static func spoken(_ seconds: Int, lang: String) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60
        var out: [String] = []
        if h > 0 { out.append(Count.noun(h, lang: lang, de: ("Stunde", "Stunden"), en: ("hour", "hours"), th: ("ชั่วโมง", "ชั่วโมง"))) }
        if m > 0 || h == 0 { out.append(Count.noun(m, lang: lang, de: ("Minute", "Minuten"), en: ("minute", "minutes"), th: ("นาที", "นาที"))) }
        return out.joined(separator: " ")
    }
}

/// 5. Zahl mit Einheit in der richtigen Mehrzahl („1 Satz“, „3 Sätze“); Thai ohne Mehrzahl.
enum Count {
    static func noun(_ n: Int, lang: String, de: (String, String), en: (String, String), th: (String, String)) -> String {
        let pair = lang == "de" ? de : (lang == "th" ? th : en)
        return "\(n) " + (n == 1 ? pair.0 : pair.1)
    }
    static func sentences(_ n: Int, lang: String) -> String {
        noun(n, lang: lang, de: ("Satz", "Sätze"), en: ("sentence", "sentences"), th: ("ประโยค", "ประโยค"))
    }
}

/// 6. Vertrauliches nicht ungefragt übersetzen oder kopieren: API-Schlüssel, Kartennummern (Luhn), IBAN-ähnliche Folgen.
enum SensitiveTextGuard {
    enum Kind: Equatable { case apiKey, cardNumber, iban }

    static func luhn(_ digits: [Int]) -> Bool {
        guard digits.count >= 13, digits.count <= 19 else { return false }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 { let x = d * 2; sum += x > 9 ? x - 9 : x } else { sum += d }
        }
        return sum % 10 == 0
    }

    static func detect(_ text: String) -> Kind? {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        for w in words {
            let s = String(w).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:\"'()"))
            if s.hasPrefix("sk-") && s.count >= 20 { return .apiKey }
            if s.count >= 32, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
               s.contains(where: { $0.isNumber }), s.contains(where: { $0.isLetter }) { return .apiKey }
        }
        let digitsOnly = text.filter { $0.isASCII && $0.isNumber }.map { Int(String($0))! }
        let compact = text.filter { !$0.isWhitespace && $0 != "-" }
        if compact.count == digitsOnly.count, luhn(digitsOnly) { return .cardNumber }
        let upper = compact.uppercased()
        if upper.count >= 15, upper.count <= 34, upper.prefix(2).allSatisfy({ $0.isASCII && $0.isLetter }),
           upper.dropFirst(2).prefix(2).allSatisfy({ $0.isASCII && $0.isNumber }),
           upper.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
           upper.filter({ $0.isNumber }).count >= 8 { return .iban }
        return nil
    }
}

/// 7. Neustart der Engine mit wachsender Pause (2, 4, 8 … höchstens 30 s) und Obergrenze der Versuche.
enum EngineRestartPlan {
    static let maxAttempts = 5
    static func delay(attempt: Int) -> TimeInterval {
        guard attempt >= 1 else { return 0 }
        return min(30, pow(2, Double(min(attempt, 10))))
    }
    static func shouldRetry(attempt: Int) -> Bool { attempt <= maxAttempts }
}

/// 8. Speicherplatz für Modelle und Verlauf.
enum DiskSpaceAdvice {
    enum Level: Equatable { case ok, low, critical }
    static func level(freeBytes: Int64) -> Level {
        if freeBytes < 500_000_000 { return .critical }
        if freeBytes < 3_000_000_000 { return .low }
        return .ok
    }
    static func text(freeBytes: Int64, lang: String) -> String? {
        let gb = String(format: "%.1f", Double(max(0, freeBytes)) / 1_000_000_000)
        switch level(freeBytes: freeBytes) {
        case .ok: return nil
        case .low: return pick(lang, de: "Wenig Speicherplatz (\(gb) GB frei). Modelle brauchen mehrere GB.",
                               en: "Low disk space (\(gb) GB free). Models need several GB.", th: "พื้นที่ดิสก์เหลือน้อย (\(gb) GB) โมเดลต้องใช้หลาย GB")
        case .critical: return pick(lang, de: "Fast kein Speicherplatz mehr (\(gb) GB frei). Bitte Platz schaffen.",
                                    en: "Almost no disk space left (\(gb) GB free). Please free some up.", th: "พื้นที่ดิสก์เกือบเต็ม (\(gb) GB) โปรดเคลียร์พื้นที่")
        }
    }
}

/// 9. Mikrofonpegel (dBFS) → Balken 0…1 und Sprechtext.
enum MicLevelText {
    static func normalized(db: Double) -> Double {
        guard db.isFinite else { return 0 }
        return min(1, max(0, (db + 60) / 60))
    }
    enum Band: Equatable { case silent, quiet, good, loud }
    static func band(db: Double) -> Band {
        let n = normalized(db: db)
        if n < 0.1 { return .silent }
        if n < 0.4 { return .quiet }
        if n < 0.9 { return .good }
        return .loud
    }
    static func spoken(db: Double, lang: String) -> String {
        switch band(db: db) {
        case .silent: return pick(lang, de: "Stille", en: "Silence", th: "เงียบ")
        case .quiet: return pick(lang, de: "leise", en: "quiet", th: "เบา")
        case .good: return pick(lang, de: "gut", en: "good", th: "ดี")
        case .loud: return pick(lang, de: "zu laut", en: "too loud", th: "ดังเกินไป")
        }
    }
}

/// 10. Hinweis, wenn die Aufnahme läuft, aber lange keine Sprache ankommt.
enum NoInputAdvice {
    static func text(listening: Bool, secondsSinceSpeech: Int, micMuted: Bool, lang: String) -> String? {
        guard listening else { return nil }
        if micMuted { return pick(lang, de: "Das Mikrofon ist stummgeschaltet.", en: "The microphone is muted.", th: "ปิดเสียงไมโครโฟนอยู่") }
        guard secondsSinceSpeech >= 30 else { return nil }
        return pick(lang, de: "Seit \(secondsSinceSpeech) Sekunden keine Sprache gehört. Mikrofon und Eingang prüfen.",
                    en: "No speech heard for \(secondsSinceSpeech) seconds. Check the microphone and input.",
                    th: "ไม่ได้ยินเสียงพูดมา \(secondsSinceSpeech) วินาที ตรวจสอบไมโครโฟนและอินพุต")
    }
}

/// 11. Dateiname für Exporte: Datum, Sprachpaar, ohne Sonderzeichen.
enum ExportFileName {
    static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var out = ""
        for u in s.unicodeScalars { out += allowed.contains(u) ? String(u) : "-" }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }
    static func make(date: Date, from: String, to: String, ext: String, calendar: Calendar = .init(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d_%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let pair = sanitize(from) + "-" + sanitize(to)
        let e = sanitize(ext).lowercased()
        return "dolmetscher_\(stamp)_\(pair)" + (e.isEmpty ? "" : "." + e)
    }
}

/// 12. Zeichenzähler für Eingabefelder: Zustand und Sprechtext.
enum CharLimit {
    enum State: Equatable { case ok, warn, over }
    static func state(count: Int, limit: Int) -> State {
        if count > limit { return .over }
        return Double(count) >= Double(limit) * 0.9 ? .warn : .ok
    }
    static func label(count: Int, limit: Int, lang: String) -> String {
        let left = limit - count
        let base = "\(count)/\(limit)"
        if left < 0 { return base + " – " + pick(lang, de: "\(-left) zu viel", en: "\(-left) over", th: "เกิน \(-left)") }
        return base
    }
}

/// 13. Einstellungen migrieren: alte Schlüssel → neue, ohne vorhandene neue Werte zu überschreiben.
enum SettingsMigration {
    static let renames: [(old: String, new: String)] = [("showTranslit", "translit"), ("fontSize", "fontScale"), ("topmost", "alwaysOnTop")]
    static func migrate(_ values: [String: Any]) -> (values: [String: Any], moved: [String]) {
        var out = values, moved: [String] = []
        for r in renames {
            guard let v = out[r.old] else { continue }
            if out[r.new] == nil { out[r.new] = v; moved.append(r.old) }
            out.removeValue(forKey: r.old)
        }
        return (out, moved)
    }
}

/// 14. Sprachpaar gesprochen: „Englisch nach Thai“ statt „en → th“.
enum PairSpeech {
    static let names: [String: [String: String]] = [
        "en": ["de": "Englisch", "en": "English", "th": "อังกฤษ"],
        "th": ["de": "Thai", "en": "Thai", "th": "ไทย"],
        "de": ["de": "Deutsch", "en": "German", "th": "เยอรมัน"],
    ]
    static func name(_ code: String, lang: String) -> String { names[code]?[lang] ?? names[code]?["en"] ?? code }
    static func spoken(from: String, to: String, lang: String) -> String {
        name(from, lang: lang) + pick(lang, de: " nach ", en: " to ", th: " เป็น ") + name(to, lang: lang)
    }
}

/// 15. Titel der Menüleiste kürzen: an Wortgrenze, mit „…“, nie leer.
enum MenuTitle {
    static func shorten(_ text: String, max: Int) -> String {
        let t = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard max > 1, t.count > max else { return t }
        let cut = String(t.prefix(max - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= max / 2 {
            return String(cut[..<space]) + "…"
        }
        return cut + "…"
    }
}

/// 16. Verlauf nach Tag gruppieren: „Heute“, „Gestern“, sonst Datum.
enum DayGroup {
    static func label(for date: Date, now: Date, lang: String, calendar: Calendar = .init(identifier: .gregorian)) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return pick(lang, de: "Heute", en: "Today", th: "วันนี้") }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return pick(lang, de: "Gestern", en: "Yesterday", th: "เมื่อวาน")
        }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
