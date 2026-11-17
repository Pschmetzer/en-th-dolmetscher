import Foundation

/// Eine Sprache der gemeinsamen Sprachtabelle `languages.json` (liegt im App-Bundle neben dolmetscher.py;
/// Engine, iPhone und Web lesen dieselbe Datei – tests/test_languages_json.py).
struct LangInfo {
    let code: String
    let flag: String
    /// Sprachkennung für AVSpeech/VoiceOver ("th-TH").
    let bcp47: String
    /// Unicode-Bereiche der eigenen Schrift; leer = lateinische Schrift.
    let script: [ClosedRange<UInt32>]
    /// Auswählbare Neural-Stimmen (Teilmenge der Engine-Liste; Englisch ohne die langsamen Multilingual-Stimmen).
    let voices: [String]
    /// „Bitte sprechen“ in dieser Sprache (Partner-Ansicht).
    let pleaseSpeak: String
}

/// Sprachtabelle und aktives Paar („meine Sprache“ + „Partnersprache“, Standard en + th).
enum Langs {
    static let all: [LangInfo] = LangTable.load(Bundle.main.url(forResource: "languages", withExtension: "json"))
    static let codes = all.map(\.code)
    static let defaultMine = "en", defaultPartner = "th"
    /// Männliche Stimmen (für „♂“ in der Stimmenauswahl).
    static let maleVoices: Set<String> = ["Guy", "Andrew", "Brian", "Ryan", "Niwat", "Christopher", "Eric", "Christoph",
                                          "Jonas", "Jan", "Alvaro", "Jorge", "Henri", "Diego", "Antonio", "Duarte",
                                          "Maarten", "Dmitry", "Yunxi", "Yunyang", "Keita", "InJoon", "NamMinh",
                                          "Ardi", "Hamed", "Shakir", "Madhur", "Ahmet", "Marek", "Ostap"]

    static func info(_ code: String) -> LangInfo? { all.first { $0.code == code } }
    static func valid(_ code: String?) -> String? { code.flatMap { codes.contains($0) ? $0 : nil } }

    /// Aktives Paar – von EngineModel gesetzt; Startwert aus den Einstellungen (alte Installationen: en/th).
    nonisolated(unsafe) static var mine = valid(UserDefaults.standard.string(forKey: "mineLang")) ?? defaultMine
    nonisolated(unsafe) static var partner = {
        let p = valid(UserDefaults.standard.string(forKey: "partnerLang")) ?? defaultPartner
        return p == mine ? (mine == defaultPartner ? defaultMine : defaultPartner) : p
    }()
    static var pair: [String] { [mine, partner] }
    static var isDefaultPair: Bool { mine == defaultMine && partner == defaultPartner }
    static var hasThai: Bool { pair.contains("th") }
    static var hasEnglish: Bool { pair.contains("en") }

    /// Steht diese Sprache auf „meiner“ Seite (Blase links, blau)? Standard: Englisch.
    static func isMine(_ code: String) -> Bool { code != partner }
    /// Zielsprache einer Äußerung: die andere Sprache des Paars.
    static func target(_ code: String) -> String { code == mine ? partner : (code == partner ? mine : partner) }
    /// Sprache der Rolle „ich“ (englisches Stimmprofil): Englisch, wenn im Paar, sonst meine Sprache (wie die Engine).
    static var meLang: String { hasEnglish ? "en" : mine }
    /// „Das war ich/Partner“: Rolle, zu der eine Blase in `code` umgebucht wird (die jeweils andere).
    static func reassignRole(_ code: String) -> String { code == meLang ? "other" : "me" }

    static func flag(_ code: String) -> String { info(code)?.flag ?? "🏳️" }
    static func bcp47(_ code: String) -> String { info(code)?.bcp47 ?? code }
    /// Name in der App-Sprache: Englisch/Thai aus der Übersetzungstabelle, sonst vom System (Locale).
    static func name(_ code: String) -> String {
        if code == "en" { return L.t("english") }
        if code == "th" { return L.t("thai") }
        let n = Locale(identifier: L.lang.rawValue).localizedString(forLanguageCode: code) ?? code.uppercased()
        return n.prefix(1).uppercased() + n.dropFirst()
    }
    static func label(_ code: String) -> String { flag(code) + " " + name(code) }

    private static func inScript(_ text: String, _ code: String) -> Bool {
        guard let r = info(code)?.script, !r.isEmpty else { return false }
        return text.unicodeScalars.contains { s in r.contains { $0.contains(s.value) } }
    }
    /// Sprache eines Schnellsatzes nach Schrift, nur zwischen den zwei Sprachen des Paars: Zeichen der eigenen
    /// Schrift einer Paarsprache -> diese; sonst die lateinische Paarsprache (meine zuerst), sonst meine.
    static func guessLang(_ text: String) -> String {
        for c in [partner, mine] where inScript(text, c) { return c }
        for c in [mine, partner] where info(c)?.script.isEmpty == true { return c }
        return mine
    }
}

/// Liest `languages.json` (Format: tests/test_languages_json.py) in die Form von `LangInfo`.
enum LangTable {
    private struct File: Decodable {
        let scripts: [String: [String]]
        let languages: [Row]
    }
    private struct Row: Decodable {
        struct Edge: Decodable { let voices: [String] }
        struct Phrases: Decodable { let please_speak: String }
        let code, flag, locale: String
        let scripts: [String]
        let edge: Edge
        let app_voices: [String]?
        let phrases: Phrases
    }

    /// "0E00-0E7F" -> 0x0E00...0x0E7F
    static func range(_ s: String) -> ClosedRange<UInt32>? {
        let p = s.split(separator: "-")
        guard p.count == 2, let a = UInt32(p[0], radix: 16), let b = UInt32(p[1], radix: 16), a <= b else { return nil }
        return a...b
    }

    static func parse(_ data: Data) -> [LangInfo]? {
        guard let f = try? JSONDecoder().decode(File.self, from: data), !f.languages.isEmpty else { return nil }
        return f.languages.map { r in
            // Lateinische Schrift = leer (guessLang: „ohne eigene Schrift“)
            let script = r.scripts.contains("latin") ? [] : r.scripts.flatMap { (f.scripts[$0] ?? []).compactMap(range) }
            return LangInfo(code: r.code, flag: r.flag, bcp47: r.locale.replacingOccurrences(of: "_", with: "-"),
                            script: script, voices: r.app_voices ?? r.edge.voices, pleaseSpeak: r.phrases.please_speak)
        }
    }

    /// Aus dem Bundle; fehlt die Datei (nur bei kaputtem Build), bleibt wenigstens das Standardpaar en/th.
    static func load(_ url: URL?) -> [LangInfo] {
        if let url, let data = try? Data(contentsOf: url), let all = parse(data) { return all }
        NSLog("Dolmetscher: languages.json fehlt im Bundle – nur Englisch/Thai")
        return [
            LangInfo(code: "en", flag: "🇬🇧", bcp47: "en-US", script: [],
                     voices: ["en-US-AriaNeural", "en-US-GuyNeural"], pleaseSpeak: "Please speak"),
            LangInfo(code: "th", flag: "🇹🇭", bcp47: "th-TH", script: [0x0E00...0x0E7F],
                     voices: ["th-TH-NiwatNeural", "th-TH-PremwadeeNeural"], pleaseSpeak: "กรุณาพูดได้เลย"),
        ]
    }
}
