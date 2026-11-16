import Foundation

/// Eine Sprache der Engine-Sprachtabelle (`LANGS` in dolmetscher.py; Codes und Stimmen prüft
/// tests/test_mehrsprachig_app.py gegen die Engine).
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
    static let all: [LangInfo] = [
        LangInfo(code: "en", flag: "🇬🇧", bcp47: "en-US", script: [],
                 voices: ["en-US-AriaNeural", "en-US-JennyNeural", "en-US-MichelleNeural", "en-US-AvaNeural",
                          "en-US-EmmaNeural", "en-US-GuyNeural", "en-US-AndrewNeural", "en-US-BrianNeural",
                          "en-GB-RyanNeural"], pleaseSpeak: "Please speak"),
        LangInfo(code: "th", flag: "🇹🇭", bcp47: "th-TH", script: [0x0E00...0x0E7F],
                 voices: ["th-TH-NiwatNeural", "th-TH-PremwadeeNeural"], pleaseSpeak: "กรุณาพูดได้เลย"),
        LangInfo(code: "de", flag: "🇩🇪", bcp47: "de-DE", script: [],
                 voices: ["de-DE-ChristophNeural", "de-DE-TanjaNeural", "de-AT-JonasNeural", "de-AT-IngridNeural",
                          "de-CH-JanNeural", "de-CH-LeniNeural"], pleaseSpeak: "Bitte sprechen Sie"),
        LangInfo(code: "es", flag: "🇪🇸", bcp47: "es-ES", script: [],
                 voices: ["es-ES-AlvaroNeural", "es-ES-ElviraNeural", "es-MX-JorgeNeural", "es-MX-DaliaNeural"],
                 pleaseSpeak: "Hable, por favor"),
        LangInfo(code: "fr", flag: "🇫🇷", bcp47: "fr-FR", script: [],
                 voices: ["fr-FR-HenriNeural", "fr-FR-DeniseNeural", "fr-FR-EloiseNeural"],
                 pleaseSpeak: "Parlez, s'il vous plaît"),
        LangInfo(code: "it", flag: "🇮🇹", bcp47: "it-IT", script: [],
                 voices: ["it-IT-DiegoNeural", "it-IT-ElsaNeural", "it-IT-IsabellaNeural"], pleaseSpeak: "Parli pure"),
        LangInfo(code: "pt", flag: "🇧🇷", bcp47: "pt-BR", script: [],
                 voices: ["pt-BR-AntonioNeural", "pt-BR-FranciscaNeural", "pt-PT-DuarteNeural", "pt-PT-RaquelNeural"],
                 pleaseSpeak: "Pode falar"),
        LangInfo(code: "nl", flag: "🇳🇱", bcp47: "nl-NL", script: [],
                 voices: ["nl-NL-MaartenNeural", "nl-NL-ColetteNeural", "nl-NL-FennaNeural"], pleaseSpeak: "Spreek maar"),
        LangInfo(code: "ru", flag: "🇷🇺", bcp47: "ru-RU", script: [0x0400...0x04FF],
                 voices: ["ru-RU-DmitryNeural", "ru-RU-SvetlanaNeural"], pleaseSpeak: "Говорите, пожалуйста"),
        LangInfo(code: "zh", flag: "🇨🇳", bcp47: "zh-CN", script: [0x3400...0x4DBF, 0x4E00...0x9FFF],
                 voices: ["zh-CN-YunxiNeural", "zh-CN-XiaoxiaoNeural", "zh-CN-YunyangNeural", "zh-CN-XiaoyiNeural"],
                 pleaseSpeak: "请说"),
        LangInfo(code: "ja", flag: "🇯🇵", bcp47: "ja-JP", script: [0x3040...0x30FF, 0x4E00...0x9FFF],
                 voices: ["ja-JP-KeitaNeural", "ja-JP-NanamiNeural"], pleaseSpeak: "どうぞお話しください"),
        LangInfo(code: "ko", flag: "🇰🇷", bcp47: "ko-KR", script: [0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F],
                 voices: ["ko-KR-InJoonNeural", "ko-KR-SunHiNeural"], pleaseSpeak: "말씀하세요"),
        LangInfo(code: "vi", flag: "🇻🇳", bcp47: "vi-VN", script: [],
                 voices: ["vi-VN-NamMinhNeural", "vi-VN-HoaiMyNeural"], pleaseSpeak: "Mời bạn nói"),
        LangInfo(code: "id", flag: "🇮🇩", bcp47: "id-ID", script: [],
                 voices: ["id-ID-ArdiNeural", "id-ID-GadisNeural"], pleaseSpeak: "Silakan bicara"),
        LangInfo(code: "ar", flag: "🇸🇦", bcp47: "ar-SA", script: [0x0600...0x06FF, 0x0750...0x077F],
                 voices: ["ar-SA-HamedNeural", "ar-SA-ZariyahNeural", "ar-EG-ShakirNeural", "ar-EG-SalmaNeural"],
                 pleaseSpeak: "تفضل بالكلام"),
        LangInfo(code: "hi", flag: "🇮🇳", bcp47: "hi-IN", script: [0x0900...0x097F],
                 voices: ["hi-IN-MadhurNeural", "hi-IN-SwaraNeural"], pleaseSpeak: "कृपया बोलिए"),
        LangInfo(code: "tr", flag: "🇹🇷", bcp47: "tr-TR", script: [],
                 voices: ["tr-TR-AhmetNeural", "tr-TR-EmelNeural"], pleaseSpeak: "Lütfen konuşun"),
        LangInfo(code: "pl", flag: "🇵🇱", bcp47: "pl-PL", script: [],
                 voices: ["pl-PL-MarekNeural", "pl-PL-ZofiaNeural"], pleaseSpeak: "Proszę mówić"),
        LangInfo(code: "uk", flag: "🇺🇦", bcp47: "uk-UA", script: [0x0400...0x04FF],
                 voices: ["uk-UA-OstapNeural", "uk-UA-PolinaNeural"], pleaseSpeak: "Говоріть, будь ласка"),
    ]
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
