// Languages.swift – Sprachtabelle (wie LANGS in dolmetscher.py), Schriften, Sprachpaar und was davon abhängt.
// Reine Logik ohne Geräte-APIs, unit-getestet.
import Foundation

/// Schriftbereiche wie SCRIPTS in dolmetscher.py.
enum Script: String, CaseIterable, Sendable {
    case latin, thai, cyrillic, han, kana, hangul, arabic, devanagari

    private var ranges: [ClosedRange<UInt32>] {
        switch self {
        case .latin: return [0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF]
        case .thai: return [0x0E00...0x0E7F]
        case .cyrillic: return [0x0400...0x04FF]
        case .han: return [0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF]
        case .kana: return [0x3040...0x30FF, 0x31F0...0x31FF]
        case .hangul: return [0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF]
        case .arabic: return [0x0600...0x06FF, 0x0750...0x077F, 0xFB50...0xFDFF, 0xFE70...0xFEFF]
        case .devanagari: return [0x0900...0x097F]
        }
    }

    func contains(_ u: Unicode.Scalar) -> Bool { ranges.contains { $0.contains(u.value) } }
}

/// Eine Sprache als Code (BCP-47-Grundcode wie in der Engine: "en", "th", "zh" …) mit Metadaten.
/// Gespeichert wird nur der Code – alte Verläufe mit "en"/"th" lesen sich unverändert.
struct Lang: RawRepresentable, Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    struct Info: Sendable {
        var english: String
        var scripts: [Script]
        /// Gebietsschema für Erkennung und Stimme (wie `locale` in LANGS)
        var locale: String
        var flag: String
        /// Code für Apples Translation (zh -> zh-Hans), sonst der Sprachcode
        var translation: String?
        /// Code für Google/MyMemory (zh -> zh-CN), sonst der Sprachcode
        var mt: String?
    }

    let rawValue: String
    var id: String { rawValue }
    var description: String { rawValue }

    /// Nur bekannte Codes (z. B. für Whisper-Sprachcodes: "lo" ist keine Sprache des Paars).
    init?(rawValue: String) {
        guard Self.table[rawValue] != nil else { return nil }
        self.rawValue = rawValue
    }

    private init(code: String) { rawValue = code }

    /// Nachsichtig: ein unbekannter Code (z. B. aus einer neueren App-Version) lässt den Verlauf nicht scheitern.
    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    var info: Info {
        Self.table[rawValue] ?? Info(english: rawValue, scripts: [.latin], locale: rawValue, flag: "🏳️")
    }
    var scripts: [Script] { info.scripts }
    var flag: String { info.flag }
    var english: String { info.english }
    /// "de_DE" -> Region "DE"
    var region: String? { info.locale.split(separator: "_").dropFirst().first.map(String.init) }
    /// Für AVSpeechSynthesisVoice: "de-DE"
    var voiceLocale: String { info.locale.replacingOccurrences(of: "_", with: "-") }
    var translationCode: String { info.translation ?? rawValue }
    var mtCode: String { info.mt ?? rawValue }

    /// Name in der Sprache der Oberfläche (über das System – keine eigene Namenstabelle).
    func name(in ui: String) -> String {
        let n = Locale(identifier: ui).localizedString(forLanguageCode: rawValue) ?? english
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    /// Eigenname („Deutsch“, „ไทย“, „日本語“).
    var native: String { name(in: rawValue) }

    static let en = Lang(code: "en"), th = Lang(code: "th"), de = Lang(code: "de"), es = Lang(code: "es"),
               fr = Lang(code: "fr"), it = Lang(code: "it"), pt = Lang(code: "pt"), nl = Lang(code: "nl"),
               ru = Lang(code: "ru"), zh = Lang(code: "zh"), ja = Lang(code: "ja"), ko = Lang(code: "ko"),
               vi = Lang(code: "vi"), id = Lang(code: "id"), ar = Lang(code: "ar"), hi = Lang(code: "hi"),
               tr = Lang(code: "tr"), pl = Lang(code: "pl"), uk = Lang(code: "uk")

    /// Reihenfolge wie LANGS in dolmetscher.py.
    static let all: [Lang] = [.en, .th, .de, .es, .fr, .it, .pt, .nl, .ru, .zh, .ja, .ko, .vi, .id, .ar, .hi, .tr, .pl, .uk]

    static let table: [String: Info] = [
        "en": Info(english: "English", scripts: [.latin], locale: "en_US", flag: "🇬🇧"),
        "th": Info(english: "Thai", scripts: [.thai], locale: "th_TH", flag: "🇹🇭"),
        "de": Info(english: "German", scripts: [.latin], locale: "de_DE", flag: "🇩🇪"),
        "es": Info(english: "Spanish", scripts: [.latin], locale: "es_ES", flag: "🇪🇸"),
        "fr": Info(english: "French", scripts: [.latin], locale: "fr_FR", flag: "🇫🇷"),
        "it": Info(english: "Italian", scripts: [.latin], locale: "it_IT", flag: "🇮🇹"),
        "pt": Info(english: "Portuguese", scripts: [.latin], locale: "pt_BR", flag: "🇧🇷"),
        "nl": Info(english: "Dutch", scripts: [.latin], locale: "nl_NL", flag: "🇳🇱"),
        "ru": Info(english: "Russian", scripts: [.cyrillic], locale: "ru_RU", flag: "🇷🇺"),
        "zh": Info(english: "Chinese", scripts: [.han], locale: "zh_CN", flag: "🇨🇳", translation: "zh-Hans", mt: "zh-CN"),
        "ja": Info(english: "Japanese", scripts: [.kana, .han], locale: "ja_JP", flag: "🇯🇵"),
        "ko": Info(english: "Korean", scripts: [.hangul], locale: "ko_KR", flag: "🇰🇷"),
        "vi": Info(english: "Vietnamese", scripts: [.latin], locale: "vi_VN", flag: "🇻🇳"),
        "id": Info(english: "Indonesian", scripts: [.latin], locale: "id_ID", flag: "🇮🇩"),
        "ar": Info(english: "Arabic", scripts: [.arabic], locale: "ar_SA", flag: "🇸🇦"),
        "hi": Info(english: "Hindi", scripts: [.devanagari], locale: "hi_IN", flag: "🇮🇳"),
        "tr": Info(english: "Turkish", scripts: [.latin], locale: "tr_TR", flag: "🇹🇷"),
        "pl": Info(english: "Polish", scripts: [.latin], locale: "pl_PL", flag: "🇵🇱"),
        "uk": Info(english: "Ukrainian", scripts: [.cyrillic], locale: "uk_UA", flag: "🇺🇦"),
    ]

    /// Anteil der Buchstaben in `text`, die zu den Schriften dieser Sprache gehören (0 ohne Buchstaben).
    func scriptShare(_ text: String) -> Double {
        var hit = 0, letters = 0
        for u in text.unicodeScalars where u.properties.isAlphabetic {
            letters += 1
            if scripts.contains(where: { $0.contains(u) }) { hit += 1 }
        }
        return letters == 0 ? 0 : Double(hit) / Double(letters)
    }
}

/// „Meine Sprache“ und „Partnersprache“. Standard en + th – ohne Einstellung ändert sich nichts.
struct LangPair: Equatable, Sendable {
    var mine: Lang
    var partner: Lang

    static let standard = LangPair(mine: .en, partner: .th)

    var langs: [Lang] { [mine, partner] }
    func contains(_ l: Lang) -> Bool { mine == l || partner == l }
    /// Die jeweils andere Sprache des Paars.
    func other(_ l: Lang) -> Lang { l == mine ? partner : mine }

    /// Getrennte Schriften (en/th, de/th, en/ja)? Nur dann kann „Automatisch“ die Sprache an der Schrift
    /// erkennen. en/de, es/fr, ru/uk und zh/ja (gemeinsame Han-Zeichen) nicht.
    var distinguishable: Bool { Set(mine.scripts).isDisjoint(with: partner.scripts) }

    var features: PairFeatures { PairFeatures(pair: self) }

    /// Aus gespeicherten Werten; ungültig oder gleich -> Standard.
    static func load(mine: String?, partner: String?) -> LangPair {
        let m = mine.flatMap(Lang.init(rawValue:)) ?? .en
        var p = partner.flatMap(Lang.init(rawValue:)) ?? (m == .th ? .en : .th)
        if p == m { p = m == .th ? .en : .th }
        return LangPair(mine: m, partner: p)
    }
}

/// Funktionen, die nur zu bestimmten Sprachen passen.
struct PairFeatures: Equatable, Sendable {
    /// Höflichkeitsform, Baht-Rechner, Thai-Notrufnummern/-karte, Thai-Satzbuch
    var thaiExtras: Bool
    /// Weckwort „Translator“ und Sprachbefehle (englisch)
    var voiceCommands: Bool

    init(pair: LangPair) {
        thaiExtras = pair.contains(.th)
        voiceCommands = pair.contains(.en)
    }
}

/// Richtung: automatisch (nur bei getrennten Schriften) oder fest von meiner bzw. der Partnersprache.
enum Direction: String, CaseIterable, Sendable {
    case auto, mine, partner

    /// Gespeicherten Wert lesen – auch die alten Werte "en"/"th" (vor dem Sprachpaar).
    static func migrate(_ raw: String?, pair: LangPair) -> Direction {
        guard let raw else { return .auto }
        if let d = Direction(rawValue: raw) { return d }
        if raw == pair.mine.rawValue { return .mine }
        if raw == pair.partner.rawValue { return .partner }
        return .auto
    }

    /// Ohne getrennte Schriften gibt es kein „Automatisch“: dann von meiner Sprache.
    func effective(_ pair: LangPair) -> Direction { self == .auto && !pair.distinguishable ? .mine : self }

    /// Welche Erkenner laufen.
    func langs(_ pair: LangPair) -> [Lang] {
        switch effective(pair) {
        case .auto: return pair.langs
        case .mine: return [pair.mine]
        case .partner: return [pair.partner]
        }
    }
}
