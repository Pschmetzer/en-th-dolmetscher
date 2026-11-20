// Engine.swift – startet die Python-Engine (dolmetscher.py --json), liest ihre Ereignisse
// und schickt Einstellungen live als JSON-Zeilen auf stdin. Vertrag: docs/PROTOKOLL.md.
import SwiftUI
import AVFoundation

/// Lateinische Umschrift für Thai-Text (ICU, ISO 11940 – buchstabengetreu, keine Aussprache-Umschrift).
enum Translit {
    static func latin(_ s: String) -> String? {
        guard s.unicodeScalars.contains(where: { (0x0E00...0x0E7F).contains($0.value) }) else { return nil }
        return s.applyingTransform(.toLatin, reverse: false)
    }
}

struct Utterance: Identifiable, Equatable {
    var id = UUID()              // bleibt beim Ersetzen erhalten (kein Scroll-Sprung)
    var uid: String?             // id der Engine (z. B. "u7"), für Korrektur und Sprachausgabe
    var translated: Bool
    var speaker: String?         // erkanntes Stimmprofil
    var lang: String             // gesprochene Sprache
    var to: String               // Sprache von `out`
    var text: String
    var out: String
    var stt: Double              // Sekunden Spracherkennung
    var tr: Double               // Sekunden Übersetzung
    var firstSound: Double?      // Sekunden bis zum ersten Ton
    var latency: Double?         // Sekunden vom Äußerungsende bis zum ersten Ton (`speaking.latency_s`)
    var readyS: Double?          // Sekunden vom Äußerungsende bis die Übersetzung fertig ist (`utt.ready_s`)
    var partial: String?         // vorläufiger Text, solange gesprochen wird (nur Platzhalter)
    var heard = false            // `partial` ist der fertig erkannte Originaltext (`heard`), Übersetzung folgt
    var heardLatin: String?      // Umschrift zu `heard`
    var lp: Double?              // Erkennungs-Konfidenz (log-prob)
    var provider: String?
    var source: String?
    var role: String?            // "me" / "other" im Zwei-Personen-Modus
    var dur: Double?             // Länge der Äußerung in Sekunden (`utt.dur`), für den SRT-Export
    var numWarn = false          // Ziffern in Original und Übersetzung stimmen nicht überein
    var back: String?            // Rückübersetzung (`back`), nur mit „Rückübersetzung zeigen“
    var alts: [String] = []      // andere Lesarten der Erkennung (nur bei unsicherem Thai mit Claude)
    var skipped = false          // wegen Rückstand nicht vorgelesen
    var cutOff = false           // Vorlesen riss mitten im Satz ab (`speak_done.partial`)
    var pending = false          // Platzhalter: wird gerade erkannt/übersetzt
    let textLatin: String?
    let outLatin: String?
    var date = Date()

    init(uid: String? = nil, translated: Bool = true, speaker: String? = nil, lang: String, to: String,
         text: String, out: String, stt: Double = 0, tr: Double = 0, lp: Double? = nil,
         provider: String? = nil, source: String? = nil, skipped: Bool = false, pending: Bool = false,
         textLatin: String? = nil, outLatin: String? = nil) {
        self.uid = uid; self.translated = translated; self.speaker = speaker
        self.lang = lang; self.to = to; self.text = text; self.out = out
        self.stt = stt; self.tr = tr; self.lp = lp; self.provider = provider; self.source = source
        self.skipped = skipped; self.pending = pending
        // Umschrift der Engine (RTGS, lesbar) hat Vorrang vor der ICU-Umschrift der App
        self.textLatin = textLatin ?? Translit.latin(text)
        self.outLatin = translated ? (outLatin ?? Translit.latin(out)) : nil
    }

    static func placeholder(_ uid: String) -> Utterance {
        Utterance(uid: uid, lang: Langs.mine, to: Langs.partner, text: "", out: "", pending: true)
    }

    var secs: Double { stt + tr }
    var lowConfidence: Bool { (lp ?? 0) < -0.6 }
}

/// Mikrofonpegel – eigenes Objekt, damit ~7 Updates/s nicht den ganzen Verlauf neu zeichnen.
@MainActor
final class LevelMeter: ObservableObject {
    @Published var rms = 0.0
    @Published var voice = false
    func reset() { rms = 0; voice = false }
}

/// Zustand des Engine-Prozesses (nicht des Mikrofons).
enum EngineState: Equatable { case stopped, starting, running }

@MainActor
final class EngineModel: NSObject, ObservableObject {
    /// Gemeinsame Instanz: App-Delegate (Boot, Hotkeys, Beenden) und Szenen nutzen dasselbe Modell.
    static let shared = EngineModel()

    @Published var items: [Utterance] = []
    @Published var status = L.t("stopped")
    /// Prozess-Zustand. Die Engine läuft dauerhaft im Hintergrund (`--idle`), das Mikrofon schaltet `listen`.
    @Published private(set) var state: EngineState = .stopped
    /// Prozess läuft (stdin offen) – Schnellsätze, Korrektur, Einstellungen live möglich.
    var running: Bool { state == .running }
    /// Modelle geladen (`ready` empfangen).
    @Published private(set) var engineReady = false
    /// Mikrofon laut Engine an (`mic`-Ereignis).
    @Published private(set) var micOn = false
    /// Nutzer möchte zuhören (Start gedrückt) – wird gesendet, sobald `ready` da ist.
    @Published private(set) var wantListen = false
    /// Start/Stopp-Knopf: rot, solange zugehört wird oder Start vorgemerkt ist.
    var active: Bool { wantListen || micOn }
    /// Engine lädt gerade (Prozess gestartet, `ready` fehlt noch).
    var loadingModel: Bool { state != .stopped && !engineReady }
    /// Median der letzten 10 Latenzen (Äußerungsende → erster Ton).
    @Published private(set) var latencyMedian: Double?
    private var latencies: [Double] = []
    /// Äußerungen, die gerade erkannt/übersetzt werden (thinking … utt/dropped).
    @Published private(set) var pendingIDs: Set<String> = []
    /// Ausgaben, die gerade vorgelesen werden (speaking … speak_done).
    @Published private(set) var speakingIDs: Set<String> = []
    var busy: Bool { !pendingIDs.isEmpty }
    var speakingNow: Bool { !speakingIDs.isEmpty }
    @Published var paused = false {
        didSet {   // Nr. 365 – nicht bei Push-to-Talk (jeder Tastendruck schaltet Pause)
            if paused != oldValue && !pushToTalk { Announcer.post(L.t(paused ? "a11y_paused" : "a11y_resumed")) }
        }
    }
    /// Rückstand laut `queue`-Ereignis.
    @Published private(set) var backlogSTT = 0
    @Published private(set) var backlogTTS = 0
    var backlog: Int { backlogSTT + backlogTTS }
    /// Dienste, die gerade nicht erreichbar sind (`net`: translate, tts).
    @Published private(set) var netDown: Set<String> = []
    /// Claude-Übersetzung laut `ready` tatsächlich aktiv.
    @Published private(set) var llmActive = false
    /// Gesetzt, wenn die Engine unerwartet endet: letzte Zeilen aus stderr.log.
    @Published var crashLog: String?
    /// Mikrofon-Zugriff verweigert (Knopf „Systemeinstellungen öffnen“).
    @Published private(set) var micDenied = false
    /// Laufender Modell-Download laut `download_progress` (nil = keiner).
    struct Download: Equatable { let model: String; let done: Int; let total: Int? }
    @Published private(set) var download: Download?
    /// Engine meldete `model_offline` (Modell fehlt, kein Internet) – für den Einrichtungs-Bildschirm.
    @Published private(set) var modelOffline = false
    /// Modell lädt seit mehr als 120 s ohne `ready`.
    @Published private(set) var loadSlow = false
    /// Stimmprofile laut `roles`: Name des englischen Profils („ich“) bzw. nil, wenn es keins gibt.
    @Published private(set) var rolesKnown = false
    @Published private(set) var rolesMe: String?
    /// Zwei-Personen-Modus ist eingeschaltet, kann aber ohne englisches Stimmprofil nicht wirken.
    var twoPersonIneffective: Bool { twoPerson && running && rolesKnown && rolesMe == nil }
    /// `hwprofile` (nur bei Modell „auto“): Chip, Speicher und gewählte Stufe.
    @Published private(set) var hwInfo: String?
    /// Protokollversion der Engine, wenn sie nicht zur App passt (nil = passt oder unbekannt).
    @Published private(set) var protocolMismatch: Int?
    static let protocolVersion = 1
    @Published private(set) var engineVersion: String?
    /// Letzter Engine-Fehler (bleibt sichtbar, bis er weggeklickt wird – der Status wird sofort überschrieben).
    @Published var lastError: (msg: String, date: Date)?
    /// Fehlercode der Engine zu `lastError` (nur gültig, wenn `lastErrorCodeDate` dessen Zeit ist) – steuert die Handlungsvorschläge.
    @Published var lastErrorCode: String?
    var lastErrorCodeDate: Date?
    /// `ready.degraded`: Modelle, die nicht geladen werden konnten (Erkennung läuft schwächer).
    @Published var degradedModels: [String] = []
    /// Wachhund: Die Engine beantwortet `ping` seit über 30 s nicht (hängt vermutlich).
    @Published private(set) var engineHung = false
    /// Vorschlag nach einer Korrektur: geänderte Wörter ins Vokabular eines Stimmprofils übernehmen.
    @Published var vocabSuggestion: (words: [String], profile: String)?
    /// Zuletzt als „zu unsicher“ verworfener Satz (`dropped` `unsure` mit `text`/`lang`): „Trotzdem übersetzen“.
    @Published var unsureDrop: (id: String, text: String, lang: String)?
    /// Übersetzung fehlgeschlagen (Netz/Anbieter): Satz zum erneuten Versuchen (Nr. 161).
    @Published var failedDrop: (id: String, text: String, lang: String)?
    /// Während der eigenen Ausgabe wurde vermutlich gesprochen (Ereignis `missed`), kurz einblenden.
    @Published var missedHint: String?
    private var missedWork: DispatchWorkItem?
    /// Aktives Szenario-Preset laut Engine (`preset`-Ereignis): id und englischer Name; nil = keins.
    @Published private(set) var activePreset: (id: String, name: String)?
    /// Kulturhinweis und Schnellsätze des aktiven Presets laut Ereignis (`note`, `phrases`); nil = aus der Datei.
    @Published private(set) var activePresetNote: [String: String]?
    @Published private(set) var activePresetPhrases: [(en: String, th: String, critical: Bool)]?
    /// Anzeigename des aktiven Presets in der Oberflächensprache.
    var activePresetName: String? {
        guard let a = activePreset else { return nil }
        return PresetCatalog.all.first { $0.id == a.id }?.name ?? a.name
    }
    /// Zeilen von der Engine, die kein gültiges JSON waren (Diagnose).
    private(set) var malformedLines = 0
    let meter = LevelMeter()

    private static let ud = UserDefaults.standard
    /// true, während Werte aus einem `command`-Ereignis übernommen werden (nicht zurückschicken).
    private var applyingRemote = false
    private func push(_ d: [String: Any]) { if !applyingRemote { send(d) } }

    @Published var speak = ud.object(forKey: "speak") as? Bool ?? true { didSet { Self.ud.set(speak, forKey: "speak"); send(["speak": speak]) } }
    @Published var trEN = ud.object(forKey: "trEN") as? Bool ?? true { didSet { Self.ud.set(trEN, forKey: "trEN"); push(["tr_en": trEN]) } }
    @Published var trTH = ud.object(forKey: "trTH") as? Bool ?? true { didSet { Self.ud.set(trTH, forKey: "trTH"); push(["tr_th": trTH]) } }
    /// Sprachpaar: meine Sprache + Partnersprache (Standard en + th; alte Installationen ohne Schlüssel: en/th).
    /// Gleiche Sprache auf beiden Seiten wird durch Tauschen verhindert. Live per `langs` an die Engine.
    @Published var mineLang = Langs.mine {
        didSet {
            if mineLang == partnerLang { partnerLang = oldValue }
            pairChanged()
        }
    }
    @Published var partnerLang = Langs.partner {
        didSet {
            if partnerLang == mineLang { mineLang = oldValue }
            pairChanged()
        }
    }
    private func pairChanged() {
        guard mineLang != partnerLang else { return }
        // Tausch (Nr. 11): didSet der Gegenseite hat das Paar schon gemeldet – nicht doppelt senden
        guard (Langs.mine, Langs.partner) != (mineLang, partnerLang) else { return }
        // Nr. 40: unveränderte Standard-Schnellsätze folgen dem Paar (eigene Listen bleiben unberührt)
        let curPhrases = Self.ud.string(forKey: Prefs.quickPhrases)
        if curPhrases == nil || curPhrases == Prefs.pairDefaults {
            Self.ud.set(Prefs.phrasesForPair(mine: mineLang, partner: partnerLang), forKey: Prefs.quickPhrases)
        }
        Self.ud.set(mineLang, forKey: "mineLang"); Self.ud.set(partnerLang, forKey: "partnerLang")
        Langs.mine = mineLang; Langs.partner = partnerLang
        if lang != "auto" && !Langs.pair.contains(lang) { lang = "auto" }
        push(langsMessage())
    }
    /// Paar samt gespeicherten Richtungen/Stimmen beider Sprachen in einer Zeile (`langs` wirkt zuerst):
    /// sonst setzte die Engine neue Paarsprachen auf „übersetzen“ und Standardstimme zurück.
    func langsMessage() -> [String: Any] {
        var d: [String: Any] = ["langs": ["mine": mineLang, "partner": partnerLang]]
        for c in [mineLang, partnerLang] { d["tr_\(c)"] = tr(c); d["voice_\(c)"] = voice(c) }
        return d
    }
    /// Übersetzen je Sprache und Neural-Stimme je Sprache. Englisch/Thai bleiben in trEN/trTH bzw.
    /// voiceEN/voiceTH (gespeicherte Werte gelten weiter), die übrigen Sprachen stehen in diesen Tabellen.
    @Published var trByLang = ud.dictionary(forKey: "trByLang") as? [String: Bool] ?? [:] {
        didSet { Self.ud.set(trByLang, forKey: "trByLang") }
    }
    @Published var voiceByLang = ud.dictionary(forKey: "voiceByLang") as? [String: String] ?? [:] {
        didSet { Self.ud.set(voiceByLang, forKey: "voiceByLang") }
    }
    func tr(_ code: String) -> Bool { code == "en" ? trEN : code == "th" ? trTH : (trByLang[code] ?? true) }
    func setTr(_ code: String, _ v: Bool) {
        if code == "en" { trEN = v } else if code == "th" { trTH = v }
        else { trByLang[code] = v; push(["tr_\(code)": v]) }
    }
    func voice(_ code: String) -> String { code == "en" ? voiceEN : code == "th" ? voiceTH : (voiceByLang[code] ?? "") }
    func setVoice(_ code: String, _ v: String) {
        if code == "en" { voiceEN = v } else if code == "th" { voiceTH = v }
        else { voiceByLang[code] = v; push(["voice_\(code)": v]) }
    }
    @Published var polite = ud.string(forKey: "polite") ?? "krub" { didSet { Self.ud.set(polite, forKey: "polite"); push(["polite": polite]) } }
    @Published var model = EngineModel.initialModel() { didSet { Self.ud.set(model, forKey: "model"); scheduleRestart() } }
    @Published var lang = ud.string(forKey: "lang") ?? "auto" { didSet { Self.ud.set(lang, forKey: "lang"); push(["lang": lang]) } }
    /// Szenario-Preset (id aus presets/*.json, "" = keins). Kein Startargument: wird nach jedem `ready` gesendet.
    @Published var preset = ud.string(forKey: "preset") ?? "" {
        didSet { Self.ud.set(preset, forKey: "preset"); push(["preset": preset.isEmpty ? "none" : preset]) }
    }
    /// Gesprächsverlauf lokal speichern (Engine: history.sqlite, Standard aus).
    @Published var history = ud.bool(forKey: "history") {
        didSet { Self.ud.set(history, forKey: "history"); push(["history": history]) }
    }

    // Stimme und Audio (live)
    @Published var rate = ud.object(forKey: "rate") as? Int ?? 0 { didSet { Self.ud.set(rate, forKey: "rate"); push(["rate": rate]) } }
    @Published var volume = ud.object(forKey: "volume") as? Double ?? 1.0 { didSet { Self.ud.set(volume, forKey: "volume"); push(["volume": volume]) } }
    @Published var voiceEN = ud.string(forKey: "voiceEN") ?? "" { didSet { Self.ud.set(voiceEN, forKey: "voiceEN"); push(["voice_en": voiceEN]) } }
    @Published var voiceTH = ud.string(forKey: "voiceTH") ?? "" { didSet { Self.ud.set(voiceTH, forKey: "voiceTH"); push(["voice_th": voiceTH]) } }
    @Published var silence = ud.object(forKey: "silence") as? Double ?? 0.8 { didSet { Self.ud.set(silence, forKey: "silence"); send(["silence": silence]) } }
    @Published var sensitivity = ud.string(forKey: "sensitivity") ?? "normal" { didSet { Self.ud.set(sensitivity, forKey: "sensitivity"); send(["sensitivity": sensitivity]) } }
    @Published var earcons = ud.bool(forKey: "earcons") { didSet { Self.ud.set(earcons, forKey: "earcons"); send(["earcons": earcons]) } }
    /// „Langsam und deutlich“: langsamere Ausgabe, einfachere Wortwahl (Claude), nie überspringen.
    @Published var slowMode = ud.bool(forKey: "slowMode") { didSet { Self.ud.set(slowMode, forKey: "slowMode"); send(["slow": slowMode]) } }
    /// Nr. 69: „Ausreden lassen“ – Sekunden Ruhe nach dem Satzende, bevor vorgelesen wird (0 = aus).
    @Published var letFinish = ud.double(forKey: "letFinish") {
        didSet { Self.ud.set(letFinish, forKey: "letFinish"); send(["let_finish": letFinish]) }
    }
    /// Nr. 171: Rückstand – "skip" (schneller + überspringen), "fast" (nur schneller), "off".
    @Published var catchUp = ud.string(forKey: "catchUp") ?? "skip" {
        didSet { Self.ud.set(catchUp, forKey: "catchUp"); send(["catch_up": catchUp]) }
    }
    /// Nr. 176: Beam-Breite der Erkennung (0 = automatisch: Umgebung/Hardware-Profil, 1 schnell … 5 genau).
    @Published var beam = ud.integer(forKey: "beam") {
        didSet { Self.ud.set(beam, forKey: "beam"); send(["beam": beam]) }   // 0: Engine kehrt zum Startwert zurück
    }
    /// Rückübersetzung klein unter der Übersetzung (Kontrolle, ob richtig verstanden).
    @Published var backTranslate = ud.bool(forKey: "backTranslate") {
        didSet { Self.ud.set(backTranslate, forKey: "backTranslate"); send(["back_translate": backTranslate]) }
    }
    /// Eigennamen aus Korrekturen automatisch ins Glossar übernehmen (Standard an).
    @Published var learnGlossary = (ud.object(forKey: "learnGlossary") as? Bool) ?? true {
        didSet { Self.ud.set(learnGlossary, forKey: "learnGlossary"); send(["learn_glossary": learnGlossary]) }
    }
    @Published var llmStyle = ud.string(forKey: "llmStyle") ?? "casual" { didSet { Self.ud.set(llmStyle, forKey: "llmStyle"); send(["style": llmStyle]) } }
    /// Geschätzte Claude-Kosten dieser Sitzung in US-Dollar (nach Preisliste, von der Engine gezählt).
    @Published private(set) var llmCostUSD = 0.0
    /// Geschätzte Claude-Kosten im laufenden Monat (über Neustarts, von der Engine gezählt).
    @Published private(set) var llmMonthUSD = 0.0
    /// Claude-Monatslimit in US-Dollar (0 = keins): darüber übersetzt die Engine mit Google (Nr. 16).
    @Published var llmBudget = ud.object(forKey: "llmBudget") as? Double ?? 0 {
        didSet {
            let v = min(10000, max(0, llmBudget.isFinite ? llmBudget : 0))
            if v != llmBudget { llmBudget = v }   // Zuweisung im eigenen didSet löst es nicht erneut aus
            Self.ud.set(llmBudget, forKey: "llmBudget"); send(["llm_budget": llmBudget])
        }
    }
    /// Eigene Wörter/Namen für die Claude-Übersetzung (eine Zeile: `Wort => Übersetzung` oder nur `Name`).
    static let glossaryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Dolmetscher/glossary.txt")
    @Published var glossary = (try? String(contentsOf: EngineModel.glossaryURL, encoding: .utf8)) ?? "" {
        didSet { scheduleGlossaryWrite() }
    }
    private var glossaryWork: DispatchWorkItem?
    /// Schreiben und Senden gebündelt (0,5 s nach der letzten Eingabe), nicht bei jedem Tastendruck.
    private func scheduleGlossaryWrite() {
        glossaryWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flushGlossary() } }
        glossaryWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }
    /// Sofort schreiben, falls eine Änderung noch aussteht (auch beim Beenden der App).
    func flushGlossary() {
        guard glossaryWork != nil else { return }
        glossaryWork?.cancel(); glossaryWork = nil
        try? FileManager.default.createDirectory(at: Self.glossaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try glossary.write(to: Self.glossaryURL, atomically: true, encoding: .utf8)
            // Das Glossar enthält oft private Namen: nur für den Nutzer lesbar.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.glossaryURL.path)
        } catch {
            NSLog("Dolmetscher: Glossar nicht gespeichert: %@", error.localizedDescription)
            lastError = (L.t("glossary_save_failed"), Date())
        }
        send(["glossary": glossary])
    }
    @Published var llm = (ud.object(forKey: "llm") as? Bool) ?? true { didSet { Self.ud.set(llm, forKey: "llm"); send(["llm": llm]) } }
    /// Neural-Stimme: nach so vielen Sekunden spricht die macOS-Ersatzstimme (0 = aus).
    @Published var ttsRace = ud.object(forKey: "ttsRace") as? Double ?? 1.4 {
        didSet {
            let r = min(3, max(0, (ttsRace * 10).rounded() / 10))   // auf 0,1 s runden
            if r != ttsRace { ttsRace = r }   // Zuweisung im eigenen didSet löst es nicht erneut aus
            Self.ud.set(ttsRace, forKey: "ttsRace"); send(["tts_race": ttsRace])
        }
    }
    /// Schnelles Satzende (Vorab-Erkennung nach kurzer Pause).
    @Published var fastEndpoint = ud.object(forKey: "fastEndpointV2") as? Bool ?? false {
        didSet { Self.ud.set(fastEndpoint, forKey: "fastEndpointV2"); send(["fast_endpoint": fastEndpoint]) }
    }
    /// Zwei-Personen-Modus: Englisch kommt von mir (Stimmprofil), jede andere Stimme spricht Thai.
    @Published var twoPerson = ud.object(forKey: "twoPerson") as? Bool ?? true {
        didSet { Self.ud.set(twoPerson, forKey: "twoPerson"); send(["two_person": twoPerson]) }
    }
    /// Vorläufigen Text schon während des Sprechens zeigen.
    @Published var partialText = ud.object(forKey: "partialText") as? Bool ?? false {   // Standard aus: ein Teiltext kann die Erkennung verzögern
        didSet { Self.ud.set(partialText, forKey: "partialText"); send(["partial": partialText]) }
    }
    // Nur beim Start wirksam – Änderung startet den Prozess neu (Zuhör-Zustand bleibt).
    @Published var llmModel = ud.string(forKey: "llmModel") ?? "claude-haiku-5-5" { didSet { Self.ud.set(llmModel, forKey: "llmModel"); scheduleRestart() } }
    /// Gewähltes Mikrofon: Index (Fallback) und Name (stabil – Indizes ändern sich beim Ein-/Ausstecken).
    /// Ändern ohne Neustart: `selectMic` schickt das Steuerfeld `mic` (Nr. 158).
    @Published var mic = ud.string(forKey: "mic") ?? "" { didSet { Self.ud.set(mic, forKey: "mic") } }
    @Published var micName = ud.string(forKey: "micName") ?? "" { didSet { Self.ud.set(micName, forKey: "micName") } }
    /// Mikrofon wählen (Einstellungen): live per Steuerfeld `mic` – Name bevorzugt (Indizes verschieben sich).
    func selectMic(index: String, name: String) {
        guard index != mic || name != micName else { return }
        mic = index; micName = name; micOverride = nil
        send(["mic": Self.micControlValue(index: index, name: name)])   // auch während des Ladens
    }
    /// Mikrofon- und Rauschfilter-Argumente für die Stimmprofil-Aufnahme (gleiches Gerät wie im Betrieb).
    var enrollArgs: [String] {
        ["--mic", micOverride ?? Self.micControlValue(index: mic, name: micName)] + (denoise ? ["--denoise"] : [])
    }
    /// Wert für das Steuerfeld `mic`: Name, sonst Index, sonst Systemstandard.
    static func micControlValue(index: String, name: String) -> String {
        !name.isEmpty ? name : (!index.isEmpty ? index : "default")
    }
    /// Ausgabegerät (Nr. 24/357): CoreAudio-UID, leer = Systemstandard. Live per Steuerfeld `output_device`.
    @Published var outputDevice = ud.string(forKey: "outputDevice") ?? "" {
        didSet {
            guard outputDevice != oldValue else { return }
            Self.ud.set(outputDevice, forKey: "outputDevice"); send(["output_device": outputDevice])
        }
    }
    @Published var outputDeviceName = ud.string(forKey: "outputDeviceName") ?? "" {
        didSet { Self.ud.set(outputDeviceName, forKey: "outputDeviceName") }
    }
    @Published var denoise = ud.bool(forKey: "denoise") { didSet { Self.ud.set(denoise, forKey: "denoise"); scheduleRestart() } }
    /// Offline-Übersetzung (Apple, on-device) als Rückfall ohne Netz. Standard an, wenn der Helfer im Bundle liegt
    /// und das System ihn ausführen kann (macOS 26.4+). Nur beim Start gelesen (`--offline-translator`).
    @Published var offlineMT = (ud.object(forKey: "offlineMT") as? Bool) ?? (Paths.bundledTranslateHelper != nil) {
        didSet { Self.ud.set(offlineMT, forKey: "offlineMT"); scheduleRestart() }
    }
    /// Privatmodus (`--private`): keine Aufwärm-Anfragen, kein GET-Rückfall mit Text in der URL. Nur beim Start.
    @Published var privateMode = ud.bool(forKey: "privateMode") {
        didSet { Self.ud.set(privateMode, forKey: "privateMode"); scheduleRestart() }
    }
    @Published var logText = ud.bool(forKey: "logText") { didSet { Self.ud.set(logText, forKey: "logText"); scheduleRestart() } }
    /// Wird nach dem Speichern/Löschen des API-Schlüssels erhöht (Engine liest ihn nur beim Start).
    @Published var keyVersion = 0 { didSet { scheduleRestart() } }
    @Published var pushToTalk = ud.bool(forKey: "pushToTalk") {
        didSet {
            Self.ud.set(pushToTalk, forKey: "pushToTalk")
            if running { setPaused(pushToTalk) }
            HotKeys.shared.install(for: self)   // globales Halte-Kürzel nur im Push-to-Talk-Modus belegen
        }
    }

    // Nur Stimmen, die schnell antworten (gemessen: erster Ton nach 0,4–0,7 s). Die Multilingual-Stimmen
    // brauchen 1,5–4 s und stehen deshalb nicht mehr zur Wahl; eine gespeicherte Auswahl bleibt gültig.
    // Stimmen je Sprache: Sprachtabelle (app/Languages.swift).
    static func voices(_ code: String) -> [String] { Langs.info(code)?.voices ?? [] }
    private static let maleVoices = Langs.maleVoices

    /// „en-US-AriaNeural“ → „Aria ♀ · US“ (lesbarer Name für die Stimmenauswahl).
    static func voiceLabel(_ v: String) -> String {
        let parts = v.split(separator: "-")
        guard parts.count >= 3 else { return v }
        var name = parts[2...].joined(separator: "-")
        let slow = name.contains("Multilingual")
        name = name.replacingOccurrences(of: "MultilingualNeural", with: "").replacingOccurrences(of: "Neural", with: "")
        let sex = maleVoices.contains(name) ? "♂" : "♀"
        return "\(name) \(sex) · \(parts[1])" + (slow ? " (" + L.t("voice_slow") + ")" : "")
    }
    /// Ungefähre USD je 1000 Sätze (Preise je Million Token wie `LLM_PRICE` in dolmetscher.py; unbekanntes Modell: Opus).
    static func costPer1000(_ model: String) -> Double {
        let p: [String: (Double, Double)] = ["claude-haiku-5-5": (0.10, 0.50), "claude-sonnet-5-5": (2.0, 10.0),
                                             "claude-opus-5-5": (4.0, 20.0)]
        let (i, o) = p[model] ?? (4.0, 20.0)
        return 1000 * (300 * i + 40 * o) / 1_000_000
    }
    static let llmModels = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]

    /// Einstellungen, die nur beim Start gelesen werden – Vergleich mit dem Stand beim Start.
    private var restartSignature: String {
        "\(model)|\(denoise)|\(llmModel)|\(logText)|\(keyVersion)|\(offlineMT)|\(privateMode)"   // Mikrofon: live per `mic`
    }
    @Published private var launchedSignature: String?
    var needsRestart: Bool { state != .stopped && launchedSignature != nil && launchedSignature != restartSignature }

    private var proc: Process?
    private var launchedAt = Date.distantPast
    private var restartWork: DispatchWorkItem?
    /// Auto-Neustart nach Absturz: Zähler (zurück auf 0 nach 60 s stabiler Laufzeit oder bei Start durch den Nutzer).
    private(set) var restartAttempts = 0
    private var envBrokenReported = false   // Nr. 402: Engine meldete `python_env_broken` vor dem Beenden
    private static let maxRestartAttempts = 3
    private var backoffWork: DispatchWorkItem?
    private var loadSlowWork: DispatchWorkItem?
    /// Mikrofonname wird gerade in einen Index aufgelöst (Prozess startet danach).
    private var resolvingMic = false
    /// Nur für den nächsten Start: gespeichertes Mikrofon nicht in der Liste -> Systemstandard ("default"),
    /// ohne die Einstellung zu überschreiben (steckt man es wieder ein, gilt es beim nächsten Start wieder).
    private var micOverride: String?
    /// Schreibzugriffe auf stdin der Engine laufen hier, nicht im Main-Thread.
    private let sendQueue = DispatchQueue(label: "dolmetscher.engine.stdin")
    /// App-Start: Engine einmal im Hintergrund laden.
    private var booted = false
    /// Zuhör-Wunsch vor einem Absturz ohne Auto-Neustart (für „Neu starten“ im Absturz-Hinweis).
    private var listenBeforeCrash = false
    /// Mikrofon an den Stimmprofil-Assistenten ausgeliehen; danach Zuhören wiederherstellen?
    private var micLent = false
    private var resumeAfterLend = false
    /// Erstes `mic`-Ereignis nach dem Start empfangen. Erst dann nimmt die Engine `listen` an
    /// (`ready` kommt beim Laden, das Mikrofon-Objekt entsteht erst danach).
    private var micKnown = false
    private var canListen: Bool { engineReady && micKnown }

    /// Neustart wegen einer Einstellung zurückgestellt, weil gerade ein Gespräch läuft
    /// (Mikrofon an, Übersetzung oder Ausgabe). Wird übernommen, sobald es ruhig ist, oder per Knopf.
    @Published private(set) var restartDeferred = false
    /// Gespeicherte Sitzung, die das Hauptfenster nur lesend statt des Live-Gesprächs zeigt (HistoryView).
    @Published var viewingSession: ViewedSession?
    /// Gespräch aktiv: ein Neustart (8–19 s Laden) würde es unterbrechen.
    private var inConversation: Bool { micOn || busy || speakingNow }

    /// Einstellung mit Neustart geändert: kurz warten (mehrere Änderungen bündeln), dann neu starten –
    /// aber nicht mitten im Gespräch.
    private func scheduleRestart() {
        restartWork?.cancel(); restartWork = nil
        guard state != .stopped else { return }
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restartWork = nil
                guard self.needsRestart else { self.restartDeferred = false; return }
                if self.inConversation { self.restartDeferred = true } else { self.restart() }
            }
        }
        restartWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    /// Zurückgestellten Neustart ausführen, sobald 2 s lang nichts mehr läuft. Direkt nach `utt` ist die id
    /// weder „busy“ noch „speaking“ – ohne die Frist ginge die letzte Ausgabe im Neustart unter.
    private var deferredWork: DispatchWorkItem?
    private func applyDeferredRestart() {
        guard restartDeferred else { return }
        deferredWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.deferredWork = nil
                guard self.restartDeferred, !self.inConversation, !self.micLent, self.state == .running else { return }
                self.restartDeferred = false
                if self.needsRestart { self.restart() }
            }
        }
        deferredWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: w)
    }

    override init() {
        super.init()
        // Absturz bei geschlossenem Fenster: macOS-Mitteilung mit „Neu starten“ (Nr. 351)
        CrashNotifier.shared.onRestart = { [weak self] in self?.restart() }
        CrashNotifier.shared.install()
        // Stimmprofil angelegt/gelöscht: laufende Engine lädt die Profile neu (kein Neustart nötig)
        NotificationCenter.default.addObserver(forName: .profilesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(["reload_profiles": true]) }
        }
        // Nach den Systemeinstellungen zurück: Mikrofon-Freigabe neu prüfen
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.micDenied, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
                self.micDenied = false
                if !self.active { self.status = self.restingStatus }
            }
        }
        // Nur für Screenshots/Tests: DOLMETSCHER_DEMO=1 füllt den Verlauf mit Beispielen.
        if ProcessInfo.processInfo.environment["DOLMETSCHER_DEMO"] != nil {
            items = [
                Utterance(uid: "u1", lang: "en", to: "th", text: "Good morning! Did you get the samples?",
                          out: "สวัสดีตอนเช้าครับ ได้รับตัวอย่างแล้วหรือยังครับ", stt: 0.7, tr: 0.5, lp: -0.15, provider: "claude"),
                Utterance(uid: "u2", lang: "th", to: "en", text: "ได้รับแล้วค่ะ สวยมากเลย",
                          out: "Yes, I got them. They are very beautiful.", stt: 0.9, tr: 0.5, lp: -0.3, provider: "google"),
                Utterance(uid: "u3", translated: false, lang: "en", to: "en", text: "OK", out: "OK", stt: 0.4),
                Utterance(uid: "u4", lang: "th", to: "en", text: "ราคาเท่าไหร่คะ",
                          out: "How much is it?", stt: 1.1, tr: 0.4, lp: -0.9, provider: "google"),
                Utterance(uid: "u5", lang: "en", to: "th", text: "Thank you very much",
                          out: "ขอบคุณมากครับ", stt: 0.5, tr: 0.3, lp: -0.2, provider: "claude", skipped: true),
                Utterance.placeholder("u6"),
            ]
            items[0].firstSound = 1.6
            items[1].firstSound = 1.8
        }
    }
    private var stdin: Pipe?
    private var buffer = Data()

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Dolmetscher/stderr.log")
    private static let logMarker = "=== Dolmetscher-Engine gestartet"

    /// stderr.log: anhängen statt überschreiben, pro Start eine Kopfzeile mit Zeitstempel.
    /// Ab 1 MB wird beim Start rotiert (stderr.log.1 … .5).
    private static func prepareLog(keep: Int = 5, maxBytes: Int = 1_000_000) -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = (try? fm.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        if size > maxBytes {
            func path(_ i: Int) -> String { i == 0 ? logURL.path : logURL.path + ".\(i)" }
            try? fm.removeItem(atPath: path(keep))
            for i in stride(from: keep - 1, through: 0, by: -1) where fm.fileExists(atPath: path(i)) {
                try? fm.moveItem(atPath: path(i), toPath: path(i + 1))
            }
        }
        let fd = open(logURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { return nil }
        let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        try? fh.write(contentsOf: Data("\n\(logMarker) \(ts) ===\n".utf8))
        return fh
    }

    /// Einstellung live an die laufende Engine schicken (eine JSON-Zeile auf stdin).
    /// Das Schreiben läuft auf einer seriellen Queue (Reihenfolge bleibt, der Main-Thread blockiert nicht,
    /// wenn die Pipe voll ist); Fehler (z. B. Engine schon weg) werden geloggt statt verschluckt.
    func send(_ d: [String: Any]) {
        guard running, let h = stdin?.fileHandleForWriting,
              var data = try? JSONSerialization.data(withJSONObject: d) else { return }
        data.append(0x0A)
        let keys = d.keys.sorted().joined(separator: ",")
        sendQueue.async {
            do { try h.write(contentsOf: data) }
            catch { NSLog("Dolmetscher: Senden an die Engine fehlgeschlagen (%@): %@", keys, "\(error)") }
        }
    }

    /// Einmalige Umstellung alter Installationen von "small" auf das genauere "medium".
    /// Gespeicherte Modellwahl (für den Erststart, bevor ein EngineModel existiert).
    static var savedModel: String { initialModel() }

    private static func initialModel() -> String {
        if !ud.bool(forKey: "migratedToMedium") {
            ud.set(true, forKey: "migratedToMedium")
            if ud.string(forKey: "model") == nil || ud.string(forKey: "model") == "small" {
                ud.set("medium", forKey: "model")
            }
        }
        return ud.string(forKey: "model") ?? "medium"
    }

    // MARK: Lebenszyklus
    // Der Prozess startet beim App-Start mit `--idle` (Modelle laden, Mikrofon aus) und bleibt geladen.
    // Start/Stopp schalten nur das Mikrofon (`listen`). Neustart nur bei Einstellungen, die die Engine
    // beim Start liest, nach einem Absturz oder über „Neu starten“.

    /// Einmal beim App-Start: Engine im Hintergrund laden.
    func boot() {
        guard !booted else { return }
        booted = true
        if ProcessInfo.processInfo.environment["DOLMETSCHER_DEMO"] != nil { return }
        // Ohne eingerichtete Umgebung startet der Einrichtungs-Bildschirm die Engine danach selbst.
        if Paths.pythonIsFallback { status = L.t("python_missing"); return }
        startEngine()
        // Nr. 377: Wunsch merken – gesendet wird `listen` erst nach `ready`
        if Self.ud.bool(forKey: Prefs.listenOnLaunch) { startListening() }
    }

    /// Engine beenden und nicht neu starten (Einrichtung: Abbrechen bzw. vor dem Austausch der venv).
    func stopEngine() {
        wantListen = false
        listenBeforeCrash = false
        stopProcess()
    }

    /// Start/Stopp-Knopf, Menüleiste, ⌃⌥D.
    func toggle() { active ? stopListening() : startListening() }

    /// Zuhören einschalten. Lädt die Engine noch, wird der Wunsch gemerkt und bei `ready` gesendet.
    func startListening() {
        guard !micLent else { return }   // Stimmprofil-Assistent nimmt gerade auf
        crashLog = nil
        wantListen = true
        restartAttempts = 0   // Nutzer hat selbst gestartet: Auto-Neustart-Zähler neu
        hungRestarts = 0
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micDenied = false
        case .notDetermined:
            status = L.t("starting")
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard self.wantListen else { return }   // inzwischen Stopp gedrückt
                        if ok { self.startListening() } else { self.wantListen = false; self.micDenied = true; self.status = L.t("nomic") }
                    }
                }
            }
            return
        default:
            wantListen = false
            micDenied = true
            status = L.t("nomic")
            return
        }
        if state == .stopped { startEngine(); return }   // `ready` sendet dann listen
        if canListen {
            send(["listen": true])
            if !micOn { status = L.t("starting") }
        } else if engineReady {
            status = L.t("starting")   // erstes `mic`-Ereignis sendet listen
        } else {
            status = L.t("loading") + " " + L.t("then_start")
        }
    }

    /// Zuhören ausschalten – Modelle bleiben geladen, der Prozess läuft weiter.
    func stopListening() {
        wantListen = false
        backoffWork?.cancel(); backoffWork = nil
        if canListen { send(["listen": false]) }
        pttWork?.cancel(); pttWork = nil; pttHolding = false
        meter.reset()
        status = restingStatus
    }

    /// Prozess neu starten; danach wieder im vorigen Zuhör-Zustand.
    /// Der neue Prozess startet erst, wenn der alte beendet ist: Die Engine räumt beim Beenden geordnet auf
    /// (Mikrofon, ffmpeg) – zwei Prozesse gleichzeitig würden um das Mikrofon und den Speicher streiten.
    func restart() {
        guard state != .starting else { return }   // wartet schon auf das Ende des alten Prozesses
        let want = wantListen || micOn || (state == .stopped && listenBeforeCrash)
        restartDeferred = false
        let old = stopProcess()
        listenBeforeCrash = false
        restartAttempts = 0
        wantListen = want           // Stopp während des Wartens setzt das zurück
        let go: () -> Void = { [weak self] in
            guard let self else { return }
            if self.wantListen && !self.micLent { self.startListening() } else { self.startEngine() }
        }
        guard let old, old.isRunning else { go(); return }
        retiringProc = old
        state = .starting              // blockiert startEngine/launchEngine, `running` ist false
        status = L.t("restarting")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let end = Date().addingTimeInterval(3)   // SIGKILL kommt nach 2 s (stopProcess)
            while old.isRunning && Date() < end { usleep(50_000) }
            if old.isRunning { kill(old.processIdentifier, SIGKILL) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.retiringProc === old else { return }
                    self.retiringProc = nil
                    self.state = .stopped
                    go()
                }
            }
        }
    }

    /// Alter Prozess, auf dessen Ende ein Neustart wartet (beim Beenden der App mit abräumen).
    private var retiringProc: Process?

    /// Beim Beenden der App: Prozess beenden und kurz warten; reagiert er nicht, SIGKILL
    /// (sonst bliebe ein verwaister Python-Prozess mit Modellen im Speicher zurück).
    func shutdown() {
        flushGlossary()
        let ps = [stopProcess(), retiringProc].compactMap { $0 }
        retiringProc = nil
        guard !ps.isEmpty else { return }
        let end = Date().addingTimeInterval(2)
        while ps.contains(where: \.isRunning) && Date() < end { usleep(50_000) }
        for p in ps where p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    /// Systemeinstellungen → Datenschutz → Mikrofon.
    func openMicrophoneSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(u)
        }
    }

    /// Mikrofon für den Stimmprofil-Assistenten freigeben (Engine bleibt geladen).
    func lendMic() {
        guard !micLent else { return }
        micLent = true
        resumeAfterLend = wantListen || micOn
        if resumeAfterLend { stopListening() }
    }

    /// Nach dem Assistenten: vorigen Zuhör-Zustand wiederherstellen.
    func returnMic() {
        guard micLent else { return }
        micLent = false
        if resumeAfterLend { resumeAfterLend = false; startListening() }
    }

    private static func f2(_ v: Double) -> String { String(format: "%.2f", v) }

    private func launchArgs(_ script: String) -> [String] {
        let lock = lang == "auto" || Langs.pair.contains(lang) ? lang : "auto"
        var args = ["-u", script, "--json", "--idle", "--model", model, "--polite", polite, "--lang", lock, "--meter",
                    "--rate", String(rate), "--volume", Self.f2(volume),
                    "--silence", Self.f2(silence), "--sensitivity", sensitivity,
                    "--llm-model", llmModel, "--llm-budget", Self.f2(llmBudget), "--style", llmStyle,
                    logText ? "--log-text" : "--no-log-text",
                    "--tts-race", Self.f2(ttsRace)]
        args.append(fastEndpoint ? "--fast-endpoint" : "--no-fast-endpoint")   // Engine-Standard ist aus
        if !twoPerson { args.append("--no-two-person") }
        args.append(partialText ? "--partial" : "--no-partial")   // Engine-Standard ist aus
        if !speak { args.append("--mute") }
        if Langs.isDefaultPair {               // en/th: dieselben Argumente wie vor der Mehrsprachigkeit
            if !trEN { args.append("--no-en") }
            if !trTH { args.append("--no-th") }
            if !voiceEN.isEmpty { args += ["--voice-en", voiceEN] }
            if !voiceTH.isEmpty { args += ["--voice-th", voiceTH] }
        } else {
            args += ["--langs", "\(mineLang),\(partnerLang)"]
            if !tr(mineLang) { args.append("--no-mine") }
            if !tr(partnerLang) { args.append("--no-partner") }
            if !voice(mineLang).isEmpty { args += ["--voice-mine", voice(mineLang)] }
            if !voice(partnerLang).isEmpty { args += ["--voice-partner", voice(partnerLang)] }
        }
        let micArg = micOverride ?? mic
        if !micArg.isEmpty { args += ["--mic", micArg] }
        if !outputDevice.isEmpty { args += ["--output-device", outputDevice] }
        if denoise { args.append("--denoise") }
        if llm { args.append("--llm") }
        if earcons { args.append("--earcons") }
        if slowMode { args.append("--slow") }
        if letFinish > 0 { args += ["--let-finish", String(letFinish)] }
        if catchUp != "skip" { args += ["--catch-up", catchUp] }
        if beam > 0 { args += ["--beam", String(beam)] }
        if backTranslate { args.append("--back-translate") }
        if !learnGlossary { args.append("--no-learn-glossary") }
        if history { args.append("--history") }
        if privateMode { args.append("--private") }
        if offlineMT, let helper = Paths.bundledTranslateHelper { args += ["--offline-translator", helper] }
        return args
    }

    /// Prozess im Leerlauf starten (`--idle`): Modelle laden, Mikrofon bleibt aus.
    /// Ist ein Mikrofonname gespeichert, wird er zuerst in den aktuellen Index aufgelöst
    /// (Indizes ändern sich beim Ein-/Ausstecken); bei Fehler oder Zeitüberschreitung gilt der gespeicherte Index.
    private func startEngine() {
        guard state == .stopped, !resolvingMic else { return }
        restartWork?.cancel(); restartWork = nil
        backoffWork?.cancel(); backoffWork = nil
        guard Bundle.main.path(forResource: "dolmetscher", ofType: "py") != nil else {
            status = L.t("script_missing"); wantListen = false; return
        }
        guard !Paths.pythonIsFallback else {
            status = "⚠️ " + L.t("python_missing"); wantListen = false
            lastError = (L.t("python_missing"), Date())
            return
        }
        guard !micName.isEmpty else { launchEngine(); return }
        resolvingMic = true
        status = L.t("mic_loading")
        var finished = false
        let finish: () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !finished else { return }
                finished = true
                self.resolvingMic = false
                self.launchEngine()
            }
        }
        micOverride = nil
        let p = EngineRunner.run(["--list-mics"], timeout: 8, onEvent: { [weak self] o in
            guard o["event"] as? String == "mics", let list = o["mics"] as? [[String: Any]] else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                var found = false
                for d in list where d["name"] as? String == self.micName {
                    let idx = (d["index"] as? String) ?? (d["index"] as? NSNumber)?.stringValue
                    if let idx, idx != self.mic { self.mic = idx }
                    found = true
                    break
                }
                // Liste kam, Name fehlt (abgezogen): alter Index wäre jetzt evtl. ein anderes Gerät
                if !found && !list.isEmpty {
                    self.micOverride = "default"
                    self.lastError = (L.t("err_mic_not_found") + " – " + self.micName, Date())
                }
            }
        }, onExit: finish)
        if p == nil { finish() }
    }

    private func launchEngine() {
        guard state == .stopped, !Paths.pythonIsFallback,
              let script = Bundle.main.path(forResource: "dolmetscher", ofType: "py") else { return }
        protocolMismatch = nil      // eine neue Engine meldet ihre Protokollversion selbst (bei `ready`)
        modelOffline = false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.python)
        p.arguments = launchArgs(script)
        p.environment = Paths.engineEnvironment()   // Schlüssel nicht in der Umgebung (ps eww), sondern per stdin unten

        let out = Pipe()
        p.standardOutput = out
        let inp = Pipe()
        p.standardInput = inp
        p.standardError = Self.prepareLog() ?? FileHandle.nullDevice
        buffer = Data(); discardingLine = false; malformedLines = 0
        resetRuntime()
        // Lese- und Ende-Handler laufen auf verschiedenen Hintergrund-Queues: das Prozessende kann die
        // letzten Zeilen (z. B. das `error` kurz vor einem Absturz) überholen. Deshalb wird das Ende erst
        // verarbeitet, wenn auch stdout zu ist (EOF reiht sich auf Main hinter alle Daten-Blöcke ein);
        // erbt ein Kindprozess stdout, gilt das Ende nach 1,5 s trotzdem.
        launchGen &+= 1
        let gen = launchGen
        endExit = nil; endStdoutClosed = false
        restartDeferred = false
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty {
                h.readabilityHandler = nil
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.endPart(gen, stdoutClosed: true) } }
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.launchGen == gen, self.proc != nil else { return }
                    self.consume(d)
                }
            }
        }
        p.terminationHandler = { [weak self] ended in
            let code = ended.terminationStatus, reason = ended.terminationReason
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.endPart(gen, exited: (code, reason))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        MainActor.assumeIsolated { self?.endPart(gen, stdoutClosed: true) }
                    }
                }
            }
        }
        do {
            try p.run()
            proc = p; stdin = inp; state = .running; paused = false
            engineReady = false; micOn = false; micKnown = false
            status = L.t("loading") + (wantListen ? " " + L.t("then_start") : "")
            launchedAt = Date()
            launchedSignature = restartSignature
            scheduleLoadSlow()
            // Claude-Schlüssel als erste Steuerzeile (Env-Variablen sind für denselben Nutzer lesbar); ein in der
            // App-Umgebung gesetzter Schlüssel (Entwickler) hat Vorrang wie bisher. Wert wird nie geloggt.
            if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? APIKeyStore.read(),
               var line = try? JSONSerialization.data(withJSONObject: ["api_key": key]) {
                line.append(0x0A)
                try? inp.fileHandleForWriting.write(contentsOf: line)
            }
            if pushToTalk { setPaused(true) }   // kein Startargument dafür – direkt per stdin
        } catch {
            state = .stopped; wantListen = false
            status = L.f("start_failed", error.localizedDescription)
        }
    }

    /// Nach 120 s ohne `ready`: Hinweis statt endlosem „Lade …“.
    private func scheduleLoadSlow() {
        loadSlowWork?.cancel(); loadSlow = false
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state != .stopped, !self.engineReady else { return }
                self.loadSlow = true
            }
        }
        loadSlowWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: w)
    }

    /// Zähler je Prozessstart: späte Rückmeldungen eines alten Prozesses werden daran erkannt.
    private var launchGen = 0
    private var endExit: (code: Int32, reason: Process.TerminationReason)?
    private var endStdoutClosed = false

    /// Prozessende erst verarbeiten, wenn Exit-Status *und* stdout-Ende (oder die Frist) da sind.
    private func endPart(_ gen: Int, exited: (Int32, Process.TerminationReason)? = nil, stdoutClosed: Bool = false) {
        guard gen == launchGen, proc != nil else { return }   // alter Start oder gewollter Stopp
        if let exited { endExit = exited }
        if stdoutClosed { endStdoutClosed = true }
        guard let e = endExit, endStdoutClosed else { return }
        endExit = nil; endStdoutClosed = false
        if !buffer.isEmpty { consume(Data([0x0A])) }   // letzte Zeile ohne Zeilenende
        engineEnded(code: e.code, reason: e.reason)
    }

    /// Unerwartetes Ende (`listen: false` beendet den Prozess nicht – kommt hier also nicht an).
    /// Bis zu dreimal automatisch neu starten (Wartezeit 1, 2, 4 s) im vorigen Zuhör-Zustand; danach
    /// Absturz-Hinweis mit verständlicher Ursache (Speicher, fehlende Python-Module, Signal).
    private func engineEnded(code: Int32, reason: Process.TerminationReason) {
        let want = wantListen || micOn
        let wasReady = engineReady   // fehlende Pflichtmodule beenden die Engine vor `ready`; spätere Treffer sind Warnungen optionaler Module
        if Date().timeIntervalSince(launchedAt) > 60 { restartAttempts = 0 }   // lief stabil: neuer Versuchsvorrat
        let tail = Self.logTail()
        state = .stopped; proc = nil; stdin = nil; launchedSignature = nil
        engineReady = false; micOn = false; micKnown = false
        loadSlowWork?.cancel(); loadSlowWork = nil; loadSlow = false
        resetRuntime()
        let signaled = reason == .uncaughtSignal
        let envBroken = envBrokenReported || (!wasReady && (tail.contains("No module named")
            || tail.contains("ModuleNotFoundError") || tail.contains("ImportError")))   // Logsuche nur für alte Engines
        envBrokenReported = false
        let message: String
        if envBroken { message = L.t("crash_env") }
        else if signaled && code == SIGKILL { message = L.t("crash_oom") }
        else if signaled { message = L.f("crash_signal", Int(code)) }
        else { message = L.t("crashed") + " (Code \(code))" }
        if !envBroken, code != 0 || signaled, restartAttempts < Self.maxRestartAttempts {
            restartAttempts += 1
            wantListen = want
            status = L.f("auto_restart_n", restartAttempts, Self.maxRestartAttempts)
            let w = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.backoffWork = nil
                    if self.state == .stopped { self.startEngine() }
                }
            }
            backoffWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + pow(2, Double(restartAttempts - 1)), execute: w)
            return
        }
        wantListen = false
        listenBeforeCrash = want
        status = message
        crashLog = tail
        Announcer.post(message, force: true)
        CrashNotifier.shared.notifyStopped(message)
    }

    /// Partner-Ansicht offen (die Partnerin liest mit): Bildschirm wachhalten.
    var partnerVisible = false { didSet { keepAwake(micOn) } }

    /// Solange zugehört wird: kein System-Ruhezustand und kein App Nap (Gespräch am Tisch, Fenster verdeckt).
    /// Der Bildschirm darf aus, außer die Partner-Ansicht ist offen (die Partnerin liest mit).
    private var awakeToken: NSObjectProtocol?
    private var awakeDisplay = false
    func keepAwake(_ on: Bool) {
        let display = on && partnerVisible
        if on, awakeToken != nil, display == awakeDisplay { return }
        if let t = awakeToken { ProcessInfo.processInfo.endActivity(t); awakeToken = nil }
        guard on else { return }
        var opts: ProcessInfo.ActivityOptions = [.userInitiated, .idleSystemSleepDisabled]
        if display { opts.insert(.idleDisplaySleepDisabled) }
        awakeToken = ProcessInfo.processInfo.beginActivity(options: opts, reason: "Dolmetscher hört zu")
        awakeDisplay = display
    }

    /// Laufzeitzustand zurücksetzen (Start, Stopp, Absturz) – sonst bleibt z. B. „busy“ hängen.
    private func resetRuntime() {
        pendingIDs.removeAll(); speakingIDs.removeAll(); engineReplayIDs.removeAll()
        unsureDrop = nil
        items.removeAll { $0.pending }
        backlogSTT = 0; backlogTTS = 0
        netDown.removeAll()
        llmActive = false
        llmCostUSD = 0
        latencies.removeAll(); latencyMedian = nil
        meter.reset()
        keepAwake(false)
        pttWork?.cancel(); pttWork = nil
        for w in hearingTimers.values { w.cancel() }
        hearingTimers.removeAll()
        rolesKnown = false; rolesMe = nil
        activePreset = nil; activePresetNote = nil; activePresetPhrases = nil
        degradedModels = []
        stopWatchdog()
    }

    /// Prozess beenden (Neustart, App-Ende). Der Zuhör-Wunsch bleibt – `restart()` braucht ihn.
    /// Reagiert die Engine nicht auf SIGTERM, folgt nach 2 s SIGKILL.
    @discardableResult
    private func stopProcess() -> Process? {
        let p = proc
        proc = nil          // vor terminate(): der terminationHandler erkennt so einen gewollten Stopp
        stdin = nil
        if let p {
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            p.terminate()
            let pp = p
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if pp.isRunning { kill(pp.processIdentifier, SIGKILL) }
            }
        }
        restartWork?.cancel(); restartWork = nil
        backoffWork?.cancel(); backoffWork = nil
        loadSlowWork?.cancel(); loadSlowWork = nil; loadSlow = false
        state = .stopped
        engineReady = false; micOn = false; micKnown = false
        download = nil
        launchedSignature = nil
        replayPausedEngine = false
        resumeWork?.cancel(); resumeWork = nil
        buffer = Data()
        resetRuntime()
        status = L.t("stopped")
        return p
    }

    /// Status, wenn das Mikrofon aus ist.
    private var restingStatus: String {
        switch state {
        case .stopped: return L.t("stopped")
        default:
            if !engineReady { return L.t("loading") + (wantListen ? " " + L.t("then_start") : "") }
            return L.t("ready_press_start")
        }
    }

    /// Status neu setzen (z. B. nach Wechsel der Oberflächensprache), wenn gerade nichts passiert.
    func refreshStatus() {
        if crashLog != nil || speakingNow { return }
        status = micOn ? idleStatus : restingStatus
    }

    /// Letzte Zeilen des aktuellen Engine-Starts aus stderr.log (nur ab der letzten Kopfzeile).
    static func logTail(_ n: Int = 25) -> String {
        guard let h = try? FileHandle(forReadingFrom: logURL) else { return L.t("log_unreadable") }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        var s = String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
        if let r = s.range(of: logMarker, options: .backwards) {
            s = String(s[r.upperBound...])
            if let nl = s.firstIndex(of: "\n") { s = String(s[nl...]) }   // Rest der Kopfzeile
        }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("experimental") }   // MPS-Warnung von PyTorch, kein Fehler
            .suffix(n)
        let t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? L.t("log_empty") : t
    }

    /// Eine Zeile über 2 MB ist kein Ereignis (Protokoll-Fehler): verwerfen statt unbegrenzt puffern.
    private static let maxLineBytes = 2_000_000

    /// Nach einer überlangen Zeile: Rest bis zum nächsten Zeilenende verwerfen (sonst würde das Ende der Zeile als
    /// „Ereignis“ gelesen und zählte als weitere ungültige Zeile).
    private var discardingLine = false

    private func consume(_ d: Data) {
        if discardingLine {
            guard let nl = d.firstIndex(of: 0x0A) else { return }
            discardingLine = false
            buffer.append(d.subdata(in: (nl + 1)..<d.endIndex))
        } else {
            buffer.append(d)
        }
        while let nl = buffer.firstIndex(of: 0x0A) {
            var line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if line.last == 0x0D { line.removeLast() }                       // CRLF tolerieren
            if line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) } // BOM tolerieren
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let ev = obj["event"] as? String else {
                if !line.isEmpty {
                    malformedLines += 1
                    if malformedLines <= 5 { NSLog("Dolmetscher: Zeile der Engine ist kein Ereignis (%d Bytes)", line.count) }
                    if malformedLines == 20 { lastError = (L.t("err_comm_garbled"), Date()) }   // gestörte Kommunikation sichtbar machen
                }
                continue
            }
            // Nr. 362: nach dem ersten `pong` zählt nur `pong` als Lebenszeichen – `level` (~7/s) kommt aus dem
            // Mikrofon-Thread und liefe auch bei hängendem Steuer-Thread weiter. Ältere Engines ohne `pong`:
            // jede Zeile (der Wachhund ist dort ohnehin aus).
            if !pongSeen || ev == "pong" {
                lastAlive = Date()
                if engineHung { engineHung = false }
            }
            handle(ev, obj)
        }
        if buffer.count > Self.maxLineBytes {
            NSLog("Dolmetscher: Zeile der Engine zu lang (%d Bytes), verworfen", buffer.count)
            buffer = Data(); malformedLines += 1; discardingLine = true
        }
    }

    private static var pausedText: String { L.t("paused") }

    /// Status nach dem Ende einer Ausgabe bzw. wenn nichts vorgelesen wird.
    private var idleStatus: String {
        if !micOn { return restingStatus }   // späte Ereignisse nach `listen: false` zeigen nicht „Hört zu“
        if paused { return pushToTalk ? "⏸ " + L.t("hold_to_talk") : Self.pausedText }
        return busy ? L.t("thinking") : L.tp("listening")
    }

    /// Position je Engine-id. Der Cache wird bei jedem Zugriff geprüft (Einträge werden an mehreren
    /// Stellen entfernt) und fällt sonst auf die lineare Suche zurück – meist trifft der Cache.
    private var indexCache: [String: Int] = [:]
    private func index(of uid: String?) -> Int? {
        guard let uid else { return nil }
        if let i = indexCache[uid], i < items.count, items[i].uid == uid { return i }
        guard let i = items.lastIndex(where: { $0.uid == uid }) else { indexCache[uid] = nil; return nil }
        if indexCache.count > 4000 { indexCache.removeAll() }
        indexCache[uid] = i
        return i
    }

    private func handle(_ ev: String, _ o: [String: Any]) {
        let id = o["id"] as? String
        switch ev {
        case "loading":   // Engine meldet, welches Modell gerade lädt (z. B. "Lade Thai-Modell …")
            let msg = o["msg"] as? String ?? ""
            // Nr. 28: `download` (stabiles Feld) statt Textsuche – einmaliger Download dauert Minuten
            let firstDownload = o["download"] as? Bool ?? false
            status = L.t(firstDownload ? "loading_download" : "loading")
                + (msg.contains("Thai") ? " (ไทย)" : msg.contains("turbo") ? " (EN+)" : "")
                + (wantListen ? " " + L.t("then_start") : "")
            if firstDownload && download == nil { download = Download(model: msg, done: 0, total: nil) }
        case "download_progress":
            if let model = o["model"] as? String {
                let name = model.split(separator: "/").last.map(String.init) ?? model
                download = Download(model: name, done: (o["done_mb"] as? NSNumber)?.intValue ?? 0,
                                    total: (o["total_mb"] as? NSNumber)?.intValue)
            }
        case "ready":
            engineReady = true
            download = nil
            loadSlowWork?.cancel(); loadSlowWork = nil; loadSlow = false
            llmActive = o["llm"] as? Bool ?? false
            engineVersion = o["engine_version"] as? String
            degradedModels = o["degraded"] as? [String] ?? []
            startWatchdog()
            Announcer.post(L.t("a11y_ready"))   // Nr. 365
            // Fehlt `protocol`, ist es eine ältere Engine (vor dem Handshake) – das ist kein Fehler.
            if let pv = (o["protocol"] as? NSNumber)?.intValue, pv != Self.protocolVersion { protocolMismatch = pv }
            else { protocolMismatch = nil }
            if !preset.isEmpty { send(["preset": preset]) }
            // Paar während des Ladens geändert: nachreichen (ältere Engines ohne `langs` kennen nur en/th)
            if let p = o["langs"] as? [String: String], p["mine"] != mineLang || p["partner"] != partnerLang {
                send(langsMessage())
            }
            if pushToTalk && !pttHolding { setPaused(true) }
            if wantListen && !micLent {
                if canListen { send(["listen": true]) }   // sonst beim ersten `mic`-Ereignis
                status = L.t("starting")
            } else {
                wantListen = false
                status = restingStatus
            }
        case "mic":
            if o["reconnecting"] as? Bool == true {   // Gerät weg, Engine verbindet neu – Zuhör-Zustand bleibt
                let n = (o["attempt"] as? NSNumber)?.intValue ?? 1
                status = n <= 5 ? L.f("mic_reconnecting", n, 5) : L.f("mic_reconnecting_long", n)
                break
            }
            let on = o["on"] as? Bool ?? false
            let first = !micKnown
            micKnown = true
            if on != micOn { Announcer.post(L.t(on ? "a11y_mic_on" : "a11y_mic_off")) }   // Nr. 365
            micOn = on
            // Mikrofon läuft wieder: ein Mikrofon-Fehlerband ist erledigt (sonst bliebe es für immer stehen).
            if on, let c = lastErrorCode, c.hasPrefix("mic_") { lastError = nil; lastErrorCode = nil }
            keepAwake(on)
            if first && !on && wantListen && !micLent {
                // Start wurde während des Ladens gedrückt: jetzt erst kann die Engine `listen` annehmen.
                if engineReady { send(["listen": true]); status = L.t("starting") }
                break
            }
            if on || engineReady { wantListen = on }   // Engine ist maßgeblich (z. B. Mikrofon ließ sich nicht öffnen)
            if on {
                if pushToTalk && !pttHolding { setPaused(true) }
            } else {
                meter.reset()
                pttWork?.cancel(); pttWork = nil; pttHolding = false
            }
            if !speakingNow { status = idleStatus }
            if !on { applyDeferredRestart() }
        case "listening":   // ändert den Sprech-Status nicht
            if id == nil { pendingIDs.remove("?") }   // ältere Engine ohne ids
            if !speakingNow { status = idleStatus }
        case "hearing":
            if let id { touchPlaceholder(id) }
            if !speakingNow && micOn { status = L.t("hearing") }
        case "partial":
            guard let id else { break }
            touchPlaceholder(id)
            let text = (o["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = index(of: id), items[i].pending, !items[i].heard, !text.isEmpty {
                items[i].partial = text
                if let l = o["lang"] as? String { items[i].lang = l }
            }
        case "heard":   // fertig erkannter Originaltext vor der Übersetzung (gleiche id wie das folgende `utt`)
            guard let id else { break }
            let text = (o["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { break }
            if let i = index(of: id), !items[i].pending { break }   // `utt` ist schon da
            touchPlaceholder(id)
            if let i = index(of: id) {
                if let l = o["lang"] as? String { items[i].lang = l }
                items[i].partial = text
                items[i].heard = true
                items[i].heardLatin = (o["text_latin"] as? String) ?? Translit.latin(text)
            }
        case "thinking":
            let key = id ?? "?"
            pendingIDs.insert(key)
            if let id {
                cancelHearingTimer(id)
                if index(of: id) == nil { items.append(.placeholder(id)); trimItems() }
            }
            if !speakingNow { status = L.t("thinking") }
        case "speaking":
            let key = id ?? "?"
            speakingIDs.insert(key)
            if !engineReplayIDs.contains(key), let i = index(of: id) {   // Wiederholung: Messwerte der Blase behalten
                if let f = o["first_s"] as? Double { items[i].firstSound = f }
                if let lat = (o["latency_s"] as? NSNumber)?.doubleValue {
                    items[i].latency = lat
                    if items[i].source == nil || items[i].source == "mic" { recordLatency(lat) }
                }
            }
            status = L.t("speaking")
        case "speak_done":
            speakingIDs.remove(id ?? "?")
            // „Nochmal sprechen“ über die Engine: eine abgebrochene Wiederholung macht die Blase nicht „übersprungen“
            let wasReplay = id.map { engineReplayIDs.remove($0) != nil } ?? false
            if o["skipped"] as? Bool == true, !wasReplay, let i = index(of: id) { items[i].skipped = true }
            if wasReplay, o["skipped"] as? Bool != true, let i = index(of: id) { items[i].skipped = false }
            if o["partial"] as? Bool == true, id != "cmd", let i = index(of: id) { items[i].cutOff = true }
            if !speakingNow { status = idleStatus }
            applyDeferredRestart()
        case "queue":
            backlogSTT = o["stt"] as? Int ?? 0
            backlogTTS = o["tts"] as? Int ?? 0
        case "level":
            meter.rms = min(1, max(0, o["rms"] as? Double ?? 0))
            meter.voice = o["voice"] as? Bool ?? false
            if meter.voice { lastVoiceAt = Date() }
        case "net":
            let what = o["what"] as? String ?? "translate"
            if o["ok"] as? Bool ?? true {
                // Netz wieder da: den zuletzt gescheiterten Satz einmal automatisch neu übersetzen
                if netDown.remove(what) != nil {
                    Announcer.post(L.t("a11y_online"))   // Nr. 365
                    if what == "translate" && failedDrop != nil { retryFailed() }
                }
            } else if netDown.insert(what).inserted { Announcer.post(L.t("a11y_offline")) }
        case "missed":
            missedHint = L.t(o["why"] as? String == "cut" ? "missed_cut" : "missed_overlap")
            missedWork?.cancel()
            let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.missedHint = nil } }
            missedWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
        case "error":
            let code = o["code"] as? String, raw = o["msg"] as? String
            if code == "model_offline" { modelOffline = true; download = nil }
            if code == "python_env_broken" { envBrokenReported = true }   // Nr. 402: Code statt Logsuche
            var msg = Self.errorText(code: code, msg: raw)
            if let s = (o["retry_in_s"] as? NSNumber)?.intValue, s > 0 { msg += " " + L.f("retry_in", s) }   // Nr. 66
            status = "⚠️ " + msg
            // Hinweis behält die Ursache der Engine (Ausnahme, Dateiname, Gerät) – nur dort, wo sie variiert
            let detail = code.map { Self.errorDetailCodes.contains($0) } == true ? raw : nil
            lastError = (msg + (detail.map { " – " + DiagnosticsLogic.redact($0, home: NSHomeDirectory(), user: NSUserName()) } ?? ""), Date())
            lastErrorCode = code; lastErrorCodeDate = lastError?.date
            Announcer.post(msg, force: true)
        case "command": applyCommand(o)
        case "dropped":
            if let id {
                cancelHearingTimer(id)
                pendingIDs.remove(id)
                items.removeAll { $0.pending && $0.uid == id }
            } else {
                pendingIDs.remove("?")
            }
            if replayPausedEngine { break }   // Echo der eigenen Wiedergabe verworfen – Status nicht ändern
            if o["code"] as? String == "unsure", let id, let text = o["text"] as? String, !text.isEmpty {
                unsureDrop = (id, text, o["lang"] as? String ?? "")
            }
            if o["code"] as? String == "translate_failed", let id, let text = o["text"] as? String, !text.isEmpty {
                failedDrop = (id, text, o["lang"] as? String ?? "")
            }
            defer { applyDeferredRestart() }
            if speakingNow { break }
            if paused { status = Self.pausedText; break }
            // `command`: Antwort kommt als `command`; `translate_failed`: `error` folgt mit der Ursache
            if let t = Self.droppedText(o["code"] as? String) { status = t }
        case "utt":
            if o["replaces"] as? String == unsureDrop?.id || o["source"] as? String == "mic" { unsureDrop = nil }
            addUtterance(o, id: id)
            applyDeferredRestart()
        case "roles":
            rolesKnown = true
            rolesMe = o["me"] as? String
        case "hwprofile":
            let chip = o["chip"] as? String ?? "?"
            let ram = (o["ram_gb"] as? NSNumber)?.doubleValue ?? 0
            let mdl = o["model"] as? String ?? "?"
            let beam = (o["beam"] as? NSNumber)?.intValue ?? 1
            hwInfo = L.f("hw_info", chip, Int(ram.rounded()), mdl, beam)
        case "preset":
            let pid = o["id"] as? String
            activePreset = pid.map { ($0, o["name"] as? String ?? $0) }
            activePresetNote = o["note"].map { Preset.parseNote($0) }
            activePresetPhrases = (o["phrases"] as? [[String: Any]]).map { Preset.parsePhrases($0) }
            applyingRemote = true   // Sprachbefehl „Translator, preset taxi“: Auswahl übernehmen, nicht zurückschicken
            if (pid ?? "") != preset { preset = pid ?? "" }
            applyingRemote = false
        case "pong": pongSeen = true; if !engineHung { hungRestarts = 0 }   // Lebenszeichen – `lastAlive` setzt schon `consume`
        case "back":   // Rückübersetzung kommt nach `utt`; unbekannte id (Blase schon weg): ignorieren
            if let t = o["text"] as? String, !t.isEmpty, let i = index(of: id) { items[i].back = t }
        case "glossary":   // Engine hat Namen aus einer Korrektur gelernt: nur die neuen Zeilen anhängen, damit
                           // noch nicht gesendete eigene Änderungen am Glossar erhalten bleiben
            if let added = o["added"] as? [String], !added.isEmpty {
                let have = Set(glossary.split(separator: "\n").map {
                    $0.components(separatedBy: "=>")[0].trimmingCharacters(in: .whitespaces).lowercased() })
                let new = added.filter { !have.contains($0.lowercased()) }
                if !new.isEmpty {
                    glossary = (glossary.isEmpty || glossary.hasSuffix("\n") ? glossary : glossary + "\n")
                        + new.joined(separator: "\n") + "\n"
                }
                status = L.f("glossary_learned", added.joined(separator: ", "))
            }
        case "llm":   // Nr. 190: Claude eingeschaltet, aber kein Schlüssel -> sichtbar statt still Google
            if o["on"] as? Bool == true, o["available"] as? Bool == false {
                lastError = (L.t("llm_unavailable"), Date())
            }
        case "control_ignored":   // Nr. 188: App schickt ein Feld, das die Engine nicht kennt (ältere Engine?)
            NSLog("Dolmetscher: Engine ignorierte Steuerfelder %@", (o["keys"] as? [String] ?? []).joined(separator: ","))
        case "llm_cost":
            llmCostUSD = (o["usd"] as? NSNumber)?.doubleValue ?? llmCostUSD
            llmMonthUSD = (o["month_usd"] as? NSNumber)?.doubleValue ?? llmMonthUSD
        default: break
        }
    }

    /// Fehlertext in der App-Sprache nach `error.code`; ohne bekannten Code der Text der Engine.
    static func errorText(code: String?, msg: String?) -> String {
        if let code, let key = errorKeys[code] { return L.t(key) }
        // Stimmerkennung (Sprechermodell) nicht ladbar – die Engine schickt dafür (noch) keinen Code
        return msg ?? L.t("error_generic")
    }
    /// Codes, deren `msg` eine wechselnde Ursache enthält: im Hinweis zusätzlich zum übersetzten Text zeigen.
    static let errorDetailCodes: Set<String> = ["translate_failed", "mic_failed", "mic_unavailable",
                                                "mic_list_failed", "ffmpeg_missing", "file_failed", "file_empty",
                                                "profiles_failed", "preset_invalid"]
    /// `error.code` (docs/PROTOKOLL.md) -> L10n-Schlüssel. Literale Schlüssel: tests/test_l10n_keys.py prüft sie.
    static let errorKeys: [String: String] = [
        "mic_denied": "err_mic_denied", "mic_unavailable": "err_mic_unavailable", "mic_no_data": "err_mic_no_data",
        "mic_timeout": "err_mic_timeout", "mic_failed": "err_mic_failed", "mic_not_found": "err_mic_not_found",
        "output_not_found": "err_output_not_found", "output_unsupported": "err_output_unsupported",
        "output_invalid": "err_output_not_found", "offline_mt_missing": "err_offline_mt_missing",
        "preset_invalid": "err_preset_invalid", "vad_failed": "err_vad_failed", "python_env_broken": "crash_env",
        "profile_name_invalid": "err_profile_name_invalid", "profile_invalid": "err_profile_invalid",
        "profile_not_found": "err_profile_not_found", "profile_delete_failed": "err_profile_delete_failed",
        "history_failed": "err_history_failed", "history_days_invalid": "err_history_days_invalid",
        "mic_list_failed": "err_mic_list_failed", "mic_file_missing": "err_mic_file_missing",
        "ffmpeg_missing": "err_ffmpeg_missing", "audio_missing": "err_audio_missing", "model_offline": "err_model_offline",
        "translate_failed": "err_translate_failed", "llm_billing": "err_llm_billing", "reassign_expired": "err_reassign_expired",
        "reassign_empty": "err_reassign_empty", "reassign_invalid": "err_reassign_invalid",
        "phrase_invalid": "err_phrase_invalid", "edit_invalid": "err_edit_invalid",
        "voice_unknown": "err_voice_unknown", "glossary_invalid": "err_glossary_invalid", "langs_invalid": "err_langs_invalid",
        "file_empty": "err_file_empty", "file_failed": "err_file_failed",
        "profiles_failed": "err_speaker_model", "speak_invalid": "err_speak_invalid",
        "llm_budget": "err_llm_budget", "mic_invalid": "err_mic_invalid",
    ]
    /// Status zu `dropped.code`; nil = Status nicht ändern.
    static func droppedText(_ code: String?) -> String? {
        switch code {
        case "command", "translate_failed", "stopped": return nil
        case let c?: return droppedKeys[c].map { $0 == "drop_other_language" ? L.tp($0) : L.t($0) } ?? L.t("dropped")
        case nil: return L.t("dropped")
        }
    }
    static let droppedKeys: [String: String] = [
        "too_short": "drop_too_short", "other_language": "drop_other_language", "locked": "drop_locked",
        "paused": "paused", "unsure": "drop_unsure", "hallucination": "dropped", "filler": "dropped",
        "empty": "dropped", "error": "drop_error", "other": "dropped",
    ]

    /// Obergrenze für die Sprechblasen im Speicher: älteste fertige Einträge fallen weg
    /// (Platzhalter und die gerade vorgelesene Blase bleiben). Der Verlauf auf der Platte ist davon unberührt.
    static let maxItems = 500
    /// Nr. 364: so viele alte Blasen sind seit dem letzten Leeren weggefallen (Export-Hinweis).
    @Published private(set) var trimmedCount = 0
    func resetTrimmed() { trimmedCount = 0 }
    /// Nr. 383: einzelne Blase löschen (Fehlerkennung, Datenschutz). Läuft sie gerade, wird das Vorlesen beendet.
    /// Nur in der App: der Verlauf (falls an) und der Gesprächskontext der Engine bleiben, bis „Alles löschen“.
    func deleteItem(_ u: Utterance) {
        if u.id == replayingID || (u.uid.map { speakingIDs.contains($0) } ?? false) { stopSpeaking() }
        // Nr. 34: Blase samt Position merken, damit „Rückgängig“ sie zurückholt (15 s – für VoiceOver/Switch-Nutzer sonst zu knapp)
        if let i = items.firstIndex(where: { $0.id == u.id }) { deletedBubble = (u, i) }
        deletedWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.deletedBubble = nil } }
        deletedWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: w)
        items.removeAll { $0.id == u.id }
        indexCache.removeAll()
        Announcer.post(L.t("bubble_deleted"))
    }
    /// Zuletzt gelöschte Blase (nil nach 15 s) – „Rückgängig“ im Hinweisband und im Menü.
    /// Nr. 36: Wunsch der Partnerin aus der Partner-Ansicht („Bitte langsamer“); Hinweisband im Hauptfenster (8 s).
    @Published var partnerRequest: String?
    private var partnerRequestWork: DispatchWorkItem?
    func partnerAsks(_ key: String) {
        partnerRequest = key
        partnerRequestWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.partnerRequest = nil } }
        partnerRequestWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: w)
        Announcer.post(L.t(key), force: true)
        NSSound.beep()
    }
    @Published var deletedBubble: (u: Utterance, index: Int)?
    private var deletedWork: DispatchWorkItem?
    func undoDelete() {
        guard let d = deletedBubble else { return }
        deletedBubble = nil; deletedWork?.cancel()
        items.insert(d.u, at: min(d.index, items.count))
        indexCache.removeAll()
    }
    /// „Alles löschen“ (Nr. 9): Anzeige leeren und der Engine das Vergessen von Kontext/Texten sagen.
    /// Ältere Engines ignorieren das unbekannte Feld `clear`.
    func clearAll() {
        items.removeAll(); trimmedCount = 0; indexCache.removeAll(); deletedBubble = nil
        viewingSession = nil
        unsureDrop = nil; failedDrop = nil; vocabSuggestion = nil
        send(["clear": true])
    }
    private func trimItems() {
        let excess = items.count - Self.maxItems
        guard excess > 0 else { return }
        var drop = excess
        items.removeAll { u in
            guard drop > 0, !u.pending, u.id != replayingID else { return false }
            drop -= 1
            return true
        }
        trimmedCount += excess - drop
        indexCache.removeAll()
    }

    // MARK: Wachhund (ping/pong)

    /// Letztes Lebenszeichen der Engine: `pong` (vor dem ersten `pong` jede gültige Zeile).
    private var lastAlive = Date()
    private var lastTick = Date()
    private var pongSeen = false
    private var pingCounter = 0
    private var watchdogGen = 0
    // Die Engine schreibt jede Steuerzeile ins Log: nicht öfter als alle 15 s pingen.
    // 45 s Frist: Langsame Steueraktionen (z. B. Profile neu laden) laufen im selben Thread wie `pong`.
    private static let pingEvery: TimeInterval = 15
    private static let hungAfter: TimeInterval = 45
    private static let hungRestartAfter: TimeInterval = 90
    private var hungRestarts = 0

    /// Nr. 21: nach dem Aufwachen sind Netzverbindungen tot und `netDown` evtl. veraltet – Zustand neu prüfen.
    func systemDidWake() {
        guard running else { return }
        netDown.removeAll()
        lastAlive = Date(); lastTick = Date()
        pingCounter += 1
        send(["ping": pingCounter])
        refreshStatus()
    }

    private func startWatchdog() {
        watchdogGen += 1
        lastAlive = Date(); lastTick = Date(); pongSeen = false; engineHung = false
        scheduleWatchdogTick(watchdogGen)
    }

    private func stopWatchdog() {
        watchdogGen += 1
        engineHung = false
    }

    private func scheduleWatchdogTick(_ gen: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pingEvery) { [weak self] in
            MainActor.assumeIsolated { self?.watchdogTick(gen) }
        }
    }

    private func watchdogTick(_ gen: Int) {
        guard gen == watchdogGen, running, engineReady else { return }
        let now = Date()
        // Ruhezustand/App Nap: großer Abstand zwischen zwei Ticks ist kein Hängen der Engine
        if now.timeIntervalSince(lastTick) > Self.pingEvery * 2.5 { lastAlive = now }
        lastTick = now
        // Ältere Engines kennen `ping` nicht: erst nach dem ersten `pong` überwachen
        if pongSeen, !engineHung, now.timeIntervalSince(lastAlive) > Self.hungAfter {
            engineHung = true
            Announcer.post(L.t("engine_hung"), force: true)
        }
        // Nr. 20: hängt die Engine lange und läuft kein Gespräch, einmal selbst neu starten (höchstens 3 Mal)
        if engineHung, now.timeIntervalSince(lastAlive) > Self.hungRestartAfter, hungRestarts < 3,
           (!busy && !speakingNow) || now.timeIntervalSince(lastAlive) > Self.hungRestartAfter * 3 {   // „busy“ darf kein ewiger Freibrief sein
            hungRestarts += 1
            CrashNotifier.shared.notifyStopped(L.t("engine_hung"))
            restart()
            return
        }
        pingCounter += 1
        send(["ping": pingCounter])
        scheduleWatchdogTick(gen)
    }

    private func applyCommand(_ o: [String: Any]) {
        applyingRemote = true
        defer { applyingRemote = false }
        if o["clear"] as? Bool == true { items.removeAll(); trimmedCount = 0; indexCache.removeAll(); viewingSession = nil; unsureDrop = nil; failedDrop = nil }
        if let p = o["langs"] as? [String: Any], let mi = Langs.valid(p["mine"] as? String),
           let pa = Langs.valid(p["partner"] as? String), mi != pa, (mi, pa) != (mineLang, partnerLang) {
            mineLang = mi                      // gleiche Sprache auf beiden Seiten tauscht didSet weg
            if partnerLang != pa { partnerLang = pa }
        }
        if let t = o["tr"] as? [String: Bool] {
            for (k, v) in t where k != "en" && k != "th" && trByLang[k] ?? true != v { trByLang[k] = v }
        }
        if let vs = o["voices"] as? [String: String] {
            for (k, v) in vs where k != "en" && k != "th" && voiceByLang[k] ?? "" != v { voiceByLang[k] = v }
        }
        if let l = o["lang"] as? String, l != lang { lang = l }
        if let p = o["polite"] as? String, p != polite { polite = p }
        if let v = o["tr_en"] as? Bool, v != trEN { trEN = v }
        if let v = o["tr_th"] as? Bool, v != trTH { trTH = v }
        if let v = (o["rate"] as? NSNumber)?.intValue, v != rate { rate = v }
        if let v = (o["volume"] as? NSNumber)?.doubleValue, v != volume { volume = v }
        if let v = o["voice_en"] as? String, v != voiceEN { voiceEN = v }
        if let v = o["voice_th"] as? String, v != voiceTH { voiceTH = v }
        if let p = o["paused"] as? Bool { paused = p }   // nur übernehmen, wenn mitgeschickt
        replayPausedEngine = false   // Nutzer hat selbst pausiert/fortgesetzt
        resumeWork?.cancel(); resumeWork = nil
        let reply = o["reply"] as? String ?? ""
        status = paused ? Self.pausedText : "🗣 " + (reply.isEmpty ? L.t("repeating") : reply)
    }

    private func addUtterance(_ o: [String: Any], id: String?) {
        let l = o["lang"] as? String ?? Langs.mine
        let translated = o["translated"] as? Bool ?? true
        var u = Utterance(uid: id, translated: translated, speaker: o["speaker"] as? String, lang: l,
                          to: o["to"] as? String ?? (translated ? Langs.target(l) : l),
                          text: o["text"] as? String ?? "", out: o["out"] as? String ?? "",
                          stt: o["stt"] as? Double ?? 0, tr: o["tr"] as? Double ?? 0,
                          lp: o["lp"] as? Double, provider: o["provider"] as? String,
                          source: o["source"] as? String,
                          textLatin: o["text_latin"] as? String, outLatin: o["out_latin"] as? String)
        u.readyS = (o["ready_s"] as? NSNumber)?.doubleValue
        u.alts = (o["alts"] as? [String]) ?? []
        u.numWarn = o["num_warn"] as? Bool ?? false
        u.dur = (o["dur"] as? NSNumber)?.doubleValue
        u.role = o["role"] as? String
        if let id { cancelHearingTimer(id); pendingIDs.remove(id) } else { pendingIDs.remove("?") }
        // Beim Ersetzen bleibt die Blasen-id erhalten: die Liste behält ihre Position (kein Scroll-Sprung).
        if let old = o["replaces"] as? String, let i = index(of: old) {
            u.id = items[i].id
            u.date = items[i].date
            if u.speaker == nil { u.speaker = items[i].speaker }
            // Korrektur: geänderte Wörter als Vokabular vorschlagen (nur fragen, nie automatisch speichern)
            if let sv = o["suggest_vocab"] as? [String], !sv.isEmpty,
               let target = items[i].speaker ?? (l == Langs.meLang ? rolesMe : nil) {
                vocabSuggestion = (Array(sv.prefix(10)), target)
            }
            items[i] = u
            if let id { items.removeAll { $0.pending && $0.uid == id } }
        } else if let id, let i = items.lastIndex(where: { $0.pending && $0.uid == id }) {
            u.id = items[i].id
            items[i] = u
        } else {
            items.append(u)
            trimItems()
        }
        // Nr. 31: wird die Übersetzung mit der Neural-Stimme vorgelesen, sagt VoiceOver sie nicht zusätzlich an
        if !u.out.isEmpty && !(speak && !u.skipped && u.translated) { Announcer.post(u.out, lang: Langs.bcp47(u.to)) }
    }

    // MARK: Platzhalter mit Teiltext

    /// Platzhalter je `hearing`-id: Läuft nach 3 s ohne weiteres Ereignis ab (z. B. `dropped` ohne id, „zu kurz“).
    private var hearingTimers: [String: DispatchWorkItem] = [:]
    private var lastVoiceAt = Date.distantPast

    /// Platzhalter für `id` anlegen (falls nötig) und die 3-s-Frist neu starten.
    private func touchPlaceholder(_ id: String) {
        if index(of: id) == nil { items.append(.placeholder(id)); trimItems() }
        guard !pendingIDs.contains(id) else { return }   // schon in Erkennung – `utt`/`dropped` räumen auf
        scheduleHearingTimeout(id)
    }

    private func scheduleHearingTimeout(_ id: String) {
        hearingTimers[id]?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hearingTimers[id] = nil
                guard !self.pendingIDs.contains(id) else { return }
                // Spricht noch jemand (Pegel), Frist verlängern – sonst springt die Blase ans Ende.
                if Date().timeIntervalSince(self.lastVoiceAt) < 1.0 { self.scheduleHearingTimeout(id); return }
                self.items.removeAll { $0.pending && $0.uid == id }
            }
        }
        hearingTimers[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: w)
    }

    private func cancelHearingTimer(_ id: String) {
        hearingTimers[id]?.cancel()
        hearingTimers[id] = nil
    }

    private func recordLatency(_ v: Double) {
        latencies.append(v)
        if latencies.count > 10 { latencies.removeFirst(latencies.count - 10) }
        let s = latencies.sorted()
        let n = s.count
        latencyMedian = n == 0 ? nil : (n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2)
    }

    // MARK: Steuerung

    func setPaused(_ p: Bool) {
        guard running else { return }
        paused = p
        replayPausedEngine = false   // sonst hebt das verzögerte Fortsetzen nach dem Vorlesen die Pause auf
        resumeWork?.cancel(); resumeWork = nil
        send(["paused": p])
        if !speakingNow { status = idleStatus }
    }

    func togglePause() { if running { setPaused(!paused) } }

    func stopSpeaking() {
        send(["stop_speaking": true])
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    /// Stimme probehören (Einstellungen): Beispielsatz der Sprache über `speak_text`, gleiche Neural-Stimme
    /// wie im Gespräch. Nur bei laufender, nicht stummer Engine.
    var canTestVoice: Bool { running && engineReady && speak }

    func testVoice(_ code: String) {
        guard canTestVoice, Langs.pair.contains(code),
              let sample = Langs.all.first(where: { $0.code == code })?.pleaseSpeak else { return }
        send(["stop_speaking": true])
        send(["speak_text": ["text": sample, "lang": code]])
    }

    /// Text aus der Zwischenablage übersetzen und vorlesen (Menüleiste, ⌃⌥C): Sprache nach Schrift, auf 1000 Zeichen gekürzt.
    func translateClipboard() {
        let raw = NSPasteboard.general.string(forType: .string)
        guard let text = ClipboardLogic.prepare(raw) else { Announcer.post(L.t("clipboard_empty"), force: true); return }
        if ClipboardLogic.wasTruncated(raw) { Announcer.post(L.t("clipboard_truncated")) }
        say(text, lang: Prefs.phraseLang(text))
    }

    func say(_ text: String, lang: String = "en") {
        // Nr. 361: erst nach `ready` – sonst puffert die Engine den Satz und spricht ihn später unerwartet
        guard engineReady else { Announcer.post(L.t("empty_loading")); return }   // nicht mehr stumm verwerfen
        send(["say": ["text": text, "lang": lang]])
    }

    /// Nr. 51: Audiodatei übersetzen (eigener Engine-Prozess `--file`, ohne Vorlesen). Ergebnisse werden Blasen.
    @Published private(set) var fileBusy = false
    private var fileProc: Process?
    /// Laufende Datei-Übersetzung abbrechen (SIGTERM, nach 2 s SIGKILL).
    func cancelTranslateFile() {
        guard let p = fileProc, p.isRunning else { return }
        p.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
    }
    func translateFile(_ url: URL) {
        guard !fileBusy else { return }
        fileBusy = true
        let args = ["--mute", "--langs", "\(Langs.mine),\(Langs.partner)", "--model", model, "--file", url.path]
        let p = EngineRunner.run(args, timeout: 1800, onEvent: { [weak self] o in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch o["event"] as? String {
                case "utt": self.addUtterance(o, id: nil)
                case "error":
                    self.lastError = (Self.errorText(code: o["code"] as? String, msg: o["msg"] as? String), Date())
                default: break
                }
            }
        }, onExit: { [weak self] in MainActor.assumeIsolated { self?.fileBusy = false; self?.fileProc = nil } })
        fileProc = p
        if p == nil { fileBusy = false; lastError = (L.t("python_missing"), Date()) }
    }

    /// Letzte vorlesbare Übersetzung (Kopfzeile, Menü ⌘R).
    var lastReplayable: Utterance? { items.last { !$0.pending && !$0.out.isEmpty } }

    /// „Letzte Übersetzung nochmal sprechen“ (Nr. 375).
    func replayLast() { if let u = lastReplayable { replay(u) } }

    /// Frei getippter Satz (Kopfzeile, Nr. 345): Sprache aus der Schrift raten, sonst meine Sprache.
    /// Höchstens 1000 Zeichen (Grenze der Engine). -> false bei leerem Text.
    @discardableResult
    func sayTyped(_ raw: String) -> Bool {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !text.isEmpty, engineReady else { return false }
        let g = Langs.guessLang(text)
        say(text, lang: Langs.pair.contains(g) ? g : mineLang)
        return true
    }

    /// „Erneut versuchen“ nach gescheiterter Übersetzung (Nr. 161).
    func retryFailed() {
        guard let d = failedDrop else { return }
        failedDrop = nil
        send(["retranslate": ["id": d.id, "text": d.text, "lang": d.lang]])
    }

    /// „Das war ich / Das war Partner“: Engine erkennt den Satz in der Sprache dieser Person neu
    /// und führt den Stimmabdruck nach.
    func reassign(_ u: Utterance, role: String) {
        guard let uid = u.uid else { return }
        send(["reassign": ["id": uid, "role": role]])
    }

    func retranslate(_ u: Utterance, text: String) {
        guard let uid = u.uid else { return }
        send(["retranslate": ["id": uid, "text": text, "lang": u.lang]])
    }

    /// „Trotzdem übersetzen“: den als zu unsicher verworfenen Satz doch übersetzen und vorlesen.
    func translateUnsure() {
        guard let d = unsureDrop else { return }
        unsureDrop = nil
        send(["retranslate": ["id": d.id, "text": d.text, "lang": d.lang]])
    }

    // MARK: Push-to-Talk

    private var pttWork: DispatchWorkItem?
    @Published private(set) var pttHolding = false

    func pttDown() {
        guard pushToTalk, running, micOn, !pttHolding else { return }   // sonst höbe es eine eigene Pause auf
        pttHolding = true
        pttWork?.cancel(); pttWork = nil
        setPaused(false)
    }

    /// Nach dem Loslassen noch kurz zuhören, damit das Satzende nicht abgeschnitten wird.
    func pttUp() {
        guard pttHolding else { return }
        pttHolding = false
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.pttHolding, self.pushToTalk else { return }
                self.pttWork = nil
                self.setPaused(true)
            }
        }
        pttWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: w)
    }

    // MARK: Wiedergabe einer Sprechblase (Engine-Neural-Stimme, sonst Systemstimme)

    private let synth = AVSpeechSynthesizer()
    @Published private(set) var replayingID: UUID?
    /// true, wenn *wir* die Engine fürs Vorlesen pausiert haben (damit sie die Wiedergabe nicht erneut übersetzt).
    private var replayPausedEngine = false
    /// Verzögertes Fortsetzen: Die Engine prüft die Pause erst nach der Erkennung eines ganzen
    /// Abschnitts – sofort fortsetzen würde das Echo der Wiedergabe doch noch übersetzen.
    private var resumeWork: DispatchWorkItem?

    /// ids, die per `speak_text` nochmal vorgelesen werden (für `speak_done`).
    private var engineReplayIDs: Set<String> = []

    func replay(_ u: Utterance) {
        guard !u.pending, !u.out.isEmpty else { return }
        // Läuft die Engine und spricht sie (nicht stumm): gleiche Neural-Stimme wie beim ersten Mal.
        // Die Engine hört ihre eigene Ausgabe nicht mit – keine Pause nötig.
        if running && engineReady && speak && Langs.pair.contains(u.to) {
            // laufende lokale Wiedergabe abbrechen; ihr didCancel setzt eine eigene Pause verzögert fort
            if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
            send(["stop_speaking": true])
            var arg: [String: Any] = ["text": u.out, "lang": u.to]
            if let uid = u.uid { arg["id"] = uid; engineReplayIDs.insert(uid) }
            send(["speak_text": arg])
            return
        }
        synth.delegate = self
        resumeWork?.cancel(); resumeWork = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        if speakingNow { send(["stop_speaking": true]) }   // sonst sprechen Engine und Wiedergabe gleichzeitig
        let s = AVSpeechUtterance(string: u.out)
        let code = Langs.bcp47(u.to)
        guard let voice = AVSpeechSynthesisVoice(language: code) else {
            // Ohne installierte Stimme spräche AVSpeech Thai mit einer fremden Stimme (Stille oder Unsinn).
            status = L.t(u.to == "th" ? "no_thai_voice" : "no_voice")
            Announcer.post(status, force: true)
            return
        }
        s.voice = voice
        // Nr. 363: Sprechtempo (−50 … 50 %) und Lautstärke aus den Einstellungen statt fester Werte
        s.rate = Self.localRate(rate)
        s.volume = VolumeLogic.systemVoice(volume)
        if running && micOn && !paused && !replayPausedEngine {
            send(["paused": true]); replayPausedEngine = true
        }
        replayingID = u.id
        synth.speak(s)
    }

    /// Tempo der Einstellungen (−50 … 50 %) auf die AVSpeech-Skala, innerhalb ihrer Grenzen.
    nonisolated static func localRate(_ pct: Int) -> Float {
        let r = AVSpeechUtteranceDefaultSpeechRate * 0.95 * (1 + Float(max(-50, min(50, pct))) / 100)
        return min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, r))
    }

    fileprivate func replayFinished() {
        guard !synth.isSpeaking else { return }
        replayingID = nil
        guard replayPausedEngine else { return }
        resumeWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.replayPausedEngine, !self.synth.isSpeaking else { return }
                self.replayPausedEngine = false
                self.resumeWork = nil
                self.send(["paused": false])
            }
        }
        resumeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
    }

    // MARK: Einstellungen zurücksetzen

    /// Alle Einstellungen auf Standard. Die @Published-Werte werden selbst zugewiesen (ihr didSet schreibt
    /// UserDefaults und schickt es an die Engine) – ein bloßes Löschen von UserDefaults ließe alte Werte
    /// im Speicher stehen. API-Schlüsseldatei, Glossar, Stimmprofile und Verlauf bleiben unberührt.
    func resetAllSettings() {
        speak = true; trEN = true; trTH = true; polite = "krub"; lang = "auto"
        mineLang = Langs.defaultMine; partnerLang = Langs.defaultPartner; trByLang = [:]; voiceByLang = [:]
        rate = 0; volume = 1.0; voiceEN = ""; voiceTH = ""
        silence = 0.8; sensitivity = "normal"; earcons = false; llmStyle = "casual"; llm = true
        slowMode = false; backTranslate = false; learnGlossary = true; letFinish = 0; catchUp = "skip"; beam = 0
        ttsRace = 1.4; fastEndpoint = false; twoPerson = true; partialText = false
        llmModel = "claude-haiku-5-5"; mic = ""; micName = ""; denoise = false; logText = false
        offlineMT = Paths.bundledTranslateHelper != nil; privateMode = false
        pushToTalk = false; model = "medium"; preset = ""; history = false
        outputDevice = ""; outputDeviceName = ""; llmBudget = 0
        for k in Prefs.resettableKeys { Self.ud.removeObject(forKey: k) }
        Self.ud.set(L.defaultCode, forKey: L.key)
        L.sync(L.defaultCode)
    }
}

extension EngineModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.replayFinished() } }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.replayFinished() } }
    }
}
