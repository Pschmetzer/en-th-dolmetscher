// SettingsLogic.swift – Einstellungen sichern und einspielen: Aufbau, Prüfung und Vergleich ohne Oberfläche.
// Nur Foundation, damit swiftc die Logik allein testen kann (tests/test_runde15_mac_settings.py).
// Die Datei enthält nie API-Schlüssel, Gesprächsinhalte, Verlauf, Mikrofon- oder Gerätenamen.
import Foundation

enum SettingValue: Equatable, Codable {
    case bool(Bool)
    case number(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        self = .text(try c.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .text(let s): try c.encode(s)
        }
    }
}

enum SettingKind {
    case bool
    case int(ClosedRange<Int>)
    case double(ClosedRange<Double>)
    case choice([String])
    case language(allowAuto: Bool)
    case text(maxLength: Int, pattern: String?)
}

/// Reiter der Einstellungen (Reihenfolge wie im Fenster).
enum SettingGroup: Int, CaseIterable {
    case general = 0, voice, translation, display
    var titleKey: String { ["tab_general", "tab_voice", "tab_translation", "tab_display"][rawValue] }
}

struct SettingSpec {
    let key: String          // Schlüssel in UserDefaults und in der Datei
    let kind: SettingKind
    let fallback: SettingValue
    let group: SettingGroup
    let labelKey: String     // L10n-Schlüssel der Beschriftung
    let helpKey: String      // L10n-Schlüssel des Erklärtexts (Tooltip)
}

struct SettingChange: Equatable {
    let key: String
    let old: SettingValue?
    let new: SettingValue
}

enum SettingsIssueKind: Equatable {
    case notJSON, wrongFormat, newerVersion(Int), badVersion
    case unknownKey, sensitiveKey, invalidValue, sameLanguages
}

struct SettingsIssue: Equatable {
    let key: String
    let kind: SettingsIssueKind
    var isFatal: Bool {
        switch kind {
        case .notJSON, .wrongFormat, .newerVersion, .badVersion: return true
        default: return false
        }
    }
}

struct SettingsProfile: Equatable {
    var quickPhrases: String?
    var glossary: String?
}

struct SettingsImport {
    var settings: [String: SettingValue] = [:]
    var profile = SettingsProfile()
    var issues: [SettingsIssue] = []
    var fatal: SettingsIssue? { issues.first { $0.isFatal } }
}

enum SettingsLogic {
    static let format = "dolmetscher-settings"
    static let version = 1
    static let maxFileBytes = 2_000_000
    static let maxPhrasesLength = 20_000
    static let maxGlossaryLength = 100_000
    static let profilePhrasesKey = "profile.quickPhrases"
    static let profileGlossaryKey = "profile.glossary"

    private static func s(_ key: String, _ kind: SettingKind, _ fallback: SettingValue, _ g: SettingGroup,
                          _ label: String, _ help: String) -> SettingSpec {
        SettingSpec(key: key, kind: kind, fallback: fallback, group: g, labelKey: label, helpKey: help)
    }

    private static let models = ["auto", "small", "medium", "best"]
    private static let modelPattern = "^[A-Za-z0-9._:-]{1,64}$"

    /// Alles, was die Datei tragen darf. Nicht dabei: Verlauf, Textprotokoll, Mikrofon, Ausgabegerät, Stimmen, Schlüssel.
    static let specs: [SettingSpec] = general + voice + translation + display

    private static let general: [SettingSpec] = [
        s("mineLang", .language(allowAuto: false), .text("en"), .general, "lang_mine", "lang_mine_help"),
        s("partnerLang", .language(allowAuto: false), .text("th"), .general, "lang_partner", "lang_partner_help"),
        s("lang", .language(allowAuto: true), .text("auto"), .general, "recognition_lang", "recognition_lang_help"),
        s("trEN", .bool, .bool(true), .general, "sl_tr_en", "tr_en_help"),
        s("trTH", .bool, .bool(true), .general, "sl_tr_th", "tr_th_help"),
        s("model", .choice(models), .text("medium"), .general, "model_label", "sh_model"),
        s("silence", .double(0.4...2.0), .number(0.8), .general, "silence", "silence_help"),
        s("sensitivity", .choice(["low", "normal", "high"]), .text("normal"), .general, "sensitivity", "sensitivity_help"),
        s("denoise", .bool, .bool(false), .general, "denoise", "sh_denoise"),
        s("twoPerson", .bool, .bool(true), .general, "sl_two_person", "two_person_help"),
        s("fastEndpointV2", .bool, .bool(false), .general, "fast_endpoint", "fast_endpoint_help"),
        s("partialText", .bool, .bool(false), .general, "partial_text", "sh_partial_text"),
        s("pushToTalk", .bool, .bool(false), .general, "push_to_talk", "push_to_talk_help"),
        s("earcons", .bool, .bool(false), .general, "earcons", "sh_earcons"),
        s("slowMode", .bool, .bool(false), .general, "slow_mode", "slow_mode_help"),
        s("letFinish", .double(0...3), .number(0), .general, "let_finish", "let_finish_help"),
        s("catchUp", .choice(["skip", "fast", "off"]), .text("skip"), .general, "catch_up", "catch_up_help"),
        s("beam", .int(0...5), .number(0), .general, "beam", "beam_help"),
        s("backTranslate", .bool, .bool(false), .general, "back_translate", "back_translate_help"),
        s("learnGlossary", .bool, .bool(true), .general, "learn_glossary", "learn_glossary_help"),
        s("offlineMT", .bool, .bool(false), .general, "offline_mt", "offline_mt_help"),
        s("privateMode", .bool, .bool(false), .general, "private_mode", "private_mode_help"),
        s("showMenuBar", .bool, .bool(true), .general, "menubar_icon", "menubar_icon_help"),
        s("spaceToggle", .bool, .bool(true), .general, "space_toggle", "space_toggle_help"),
        s("announceTranslations", .bool, .bool(true), .general, "announce_toggle", "announce_help"),
        s("hideFromCapture", .bool, .bool(false), .general, "hide_capture", "hide_capture_help"),
        s("stopMicOnClose", .bool, .bool(true), .general, "stop_mic_on_close", "stop_mic_on_close_help"),
        s("hotkeyHUD", .bool, .bool(true), .general, "hotkey_hud", "sh_hotkey_hud"),
        s("listenOnLaunch", .bool, .bool(false), .general, "listen_on_launch", "listen_on_launch_help"),
    ]

    private static let voice: [SettingSpec] = [
        s("speak", .bool, .bool(true), .voice, "speak_toggle", "sh_speak"),
        s("polite", .choice(["krub", "ka"]), .text("krub"), .voice, "polite_label", "sh_polite"),
        s("rate", .int(-50...50), .number(0), .voice, "rate", "sh_rate"),
        s("volume", .double(0.2...2.0), .number(1), .voice, "volume", "sh_volume"),
        s("ttsRace", .double(0...3), .number(1.4), .voice, "tts_race", "tts_race_help"),
    ]

    private static let translation: [SettingSpec] = [
        s("llm", .bool, .bool(true), .translation, "llm", "sh_llm"),
        s("llmModel", .text(maxLength: 64, pattern: modelPattern), .text("claude-haiku-5-5"), .translation,
          "llm_model", "sh_llm_model"),
        s("llmStyle", .choice(["casual", "neutral", "polite"]), .text("casual"), .translation, "style", "sh_style"),
        s("llmBudget", .double(0...10_000), .number(0), .translation, "llm_budget", "llm_budget_help"),
        s("preset", .text(maxLength: 32, pattern: "^([a-z0-9_-]{1,32})?$"), .text(""), .translation,
          "preset", "preset_help"),
    ]

    private static let display: [SettingSpec] = [
        s("fontScale", .double(0.6...2.5), .number(1), .display, "font_size", "sh_font_size"),
        s("alwaysOnTop", .bool, .bool(false), .display, "always_on_top", "sh_always_on_top"),
        s("showDetails", .bool, .bool(false), .display, "show_details", "sh_show_details"),
        s("translit", .bool, .bool(true), .display, "translit", "sh_translit"),
        s("showQuickPhrases", .bool, .bool(true), .display, "show_quick", "sh_show_quick"),
        s("uiLang", .choice(["de", "en", "th"]), .text("en"), .display, "ui_language", "sh_ui_language"),
    ]

    static func spec(_ key: String) -> SettingSpec? { specs.first { $0.key == key } }

    // MARK: Wert prüfen

    /// Prüft einen Wert aus der Datei gegen die Vorgabe des Feldes; nil = ungültig.
    static func validate(_ raw: Any, for spec: SettingSpec, languages: Set<String>) -> SettingValue? {
        switch spec.kind {
        case .bool:
            return asBool(raw).map { .bool($0) }
        case .int(let r):
            guard let d = asNumber(raw), d == d.rounded(), abs(d) < 1e6, r.contains(Int(d)) else { return nil }
            return .number(d)
        case .double(let r):
            guard let d = asNumber(raw), r.contains(d) else { return nil }
            return .number(d)
        case .choice(let options):
            guard let t = raw as? String, options.contains(t) else { return nil }
            return .text(t)
        case .language(let allowAuto):
            guard let t = raw as? String, languages.contains(t) || (allowAuto && t == "auto") else { return nil }
            return .text(t)
        case .text(let maxLength, let pattern):
            guard let t = raw as? String, t.count <= maxLength else { return nil }
            if let p = pattern, t.range(of: p, options: .regularExpression) == nil { return nil }
            return .text(t)
        }
    }

    private static func asBool(_ raw: Any) -> Bool? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    private static func asNumber(_ raw: Any) -> Double? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    private static let sensitiveWords = ["key", "token", "secret", "password", "passwort", "history", "verlauf", "transcript", "log"]

    private static func looksSensitive(_ key: String) -> Bool {
        let k = key.lowercased()
        return sensitiveWords.contains { k.contains($0) }
    }

    // MARK: Datei bauen

    static func export(values: [String: SettingValue], profile: SettingsProfile, exportedAt: Date) -> Data {
        var settings: [String: Any] = [:]
        for sp in specs { settings[sp.key] = jsonValue(values[sp.key] ?? sp.fallback) }
        var prof: [String: Any] = [:]
        if let p = profile.quickPhrases { prof["quickPhrases"] = String(p.prefix(maxPhrasesLength)) }
        if let g = profile.glossary { prof["glossary"] = String(g.prefix(maxGlossaryLength)) }
        let root: [String: Any] = [
            "format": format, "version": version,
            "exportedAt": ISO8601DateFormatter().string(from: exportedAt),
            "settings": settings, "profile": prof,
        ]
        let opts: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        return (try? JSONSerialization.data(withJSONObject: root, options: opts)) ?? Data()
    }

    private static func jsonValue(_ v: SettingValue) -> Any {
        switch v {
        case .bool(let b): return b
        case .number(let d): return d
        case .text(let t): return t
        }
    }

    // MARK: Datei lesen

    static func parse(_ data: Data, languages: Set<String>) -> SettingsImport {
        var out = SettingsImport()
        guard data.count <= maxFileBytes, let obj = try? JSONSerialization.jsonObject(with: data),
              let root = obj as? [String: Any] else {
            out.issues.append(SettingsIssue(key: "", kind: .notJSON)); return out
        }
        guard root["format"] as? String == format else {
            out.issues.append(SettingsIssue(key: "format", kind: .wrongFormat)); return out
        }
        guard let ver = asNumber(root["version"] as Any), ver == ver.rounded(), ver >= 1, ver < 1e6 else {
            out.issues.append(SettingsIssue(key: "version", kind: .badVersion)); return out
        }
        if Int(ver) > version {
            out.issues.append(SettingsIssue(key: "version", kind: .newerVersion(Int(ver)))); return out
        }
        readSettings(root["settings"], into: &out, languages: languages)
        readProfile(root["profile"], into: &out)
        return out
    }

    private static func readSettings(_ raw: Any?, into out: inout SettingsImport, languages: Set<String>) {
        guard let dict = raw as? [String: Any] else { return }
        for key in dict.keys.sorted() {
            guard let sp = spec(key) else {
                let kind: SettingsIssueKind = looksSensitive(key) ? .sensitiveKey : .unknownKey
                out.issues.append(SettingsIssue(key: key, kind: kind)); continue
            }
            if let v = validate(dict[key] as Any, for: sp, languages: languages) {
                out.settings[key] = v
            } else {
                out.issues.append(SettingsIssue(key: key, kind: .invalidValue))
            }
        }
        if let a = out.settings["mineLang"], a == out.settings["partnerLang"] {
            out.settings["partnerLang"] = nil
            out.issues.append(SettingsIssue(key: "partnerLang", kind: .sameLanguages))
        }
    }

    private static func readProfile(_ raw: Any?, into out: inout SettingsImport) {
        guard let dict = raw as? [String: Any] else { return }
        for key in dict.keys.sorted() {
            let text = dict[key] as? String
            switch key {
            case "quickPhrases":
                if let t = text, t.count <= maxPhrasesLength { out.profile.quickPhrases = t }
                else { out.issues.append(SettingsIssue(key: profilePhrasesKey, kind: .invalidValue)) }
            case "glossary":
                if let t = text, t.count <= maxGlossaryLength { out.profile.glossary = t }
                else { out.issues.append(SettingsIssue(key: profileGlossaryKey, kind: .invalidValue)) }
            default:
                let kind: SettingsIssueKind = looksSensitive(key) ? .sensitiveKey : .unknownKey
                out.issues.append(SettingsIssue(key: "profile." + key, kind: kind))
            }
        }
    }

    // MARK: Vergleich

    /// Nur was sich ändern würde; Reihenfolge wie in `specs`, Profil-Texte zuletzt.
    static func diff(current: [String: SettingValue], currentProfile: SettingsProfile,
                     imported: SettingsImport) -> [SettingChange] {
        var out: [SettingChange] = []
        for sp in specs {
            guard let new = imported.settings[sp.key] else { continue }
            let old = current[sp.key] ?? sp.fallback
            if old != new { out.append(SettingChange(key: sp.key, old: old, new: new)) }
        }
        if let p = imported.profile.quickPhrases, p != currentProfile.quickPhrases {
            let old = currentProfile.quickPhrases.map { SettingValue.text($0) }
            out.append(SettingChange(key: profilePhrasesKey, old: old, new: .text(p)))
        }
        if let g = imported.profile.glossary, g != currentProfile.glossary {
            let old = currentProfile.glossary.map { SettingValue.text($0) }
            out.append(SettingChange(key: profileGlossaryKey, old: old, new: .text(g)))
        }
        return out
    }

    /// Nicht-leere Zeilen eines Profil-Textes (für die Vorschau „12 Zeilen“).
    static func lineCount(_ t: String) -> Int {
        t.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    // MARK: „Zuletzt geändert“

    /// Vergleicht zwei Stände und stempelt jede geänderte Einstellung mit `now`.
    /// Ohne alten Stand (erster Start) bleibt das Protokoll unverändert.
    static func noteChanges(old: [String: SettingValue]?, new: [String: SettingValue],
                            log: [String: Date], now: Date) -> [String: Date] {
        guard let old else { return log }
        var out = log
        for (k, v) in new where old[k] != v { out[k] = now }
        return out
    }

    /// Die neuesten Änderungen, neueste zuerst; nur bekannte Schlüssel.
    static func recent(_ log: [String: Date], limit: Int) -> [(key: String, date: Date)] {
        let known = log.filter { spec($0.key) != nil || $0.key.hasPrefix("profile.") }
        let sorted = known.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return sorted.prefix(limit).map { (key: $0.key, date: $0.value) }
    }
}
