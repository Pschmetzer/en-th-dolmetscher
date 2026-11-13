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
    let id = UUID()
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
    var lp: Double?              // Erkennungs-Konfidenz (log-prob)
    var provider: String?
    var source: String?
    var role: String?            // "me" / "other" im Zwei-Personen-Modus
    var numWarn = false          // Ziffern in Original und Übersetzung stimmen nicht überein
    var alts: [String] = []      // andere Lesarten der Erkennung (nur bei unsicherem Thai mit Claude)
    var skipped = false          // wegen Rückstand nicht vorgelesen
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
        Utterance(uid: uid, lang: "en", to: "th", text: "", out: "", pending: true)
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
    @Published var paused = false
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
    let meter = LevelMeter()

    private static let ud = UserDefaults.standard
    /// true, während Werte aus einem `command`-Ereignis übernommen werden (nicht zurückschicken).
    private var applyingRemote = false
    private func push(_ d: [String: Any]) { if !applyingRemote { send(d) } }

    @Published var speak = ud.object(forKey: "speak") as? Bool ?? true { didSet { Self.ud.set(speak, forKey: "speak"); send(["speak": speak]) } }
    @Published var trEN = ud.object(forKey: "trEN") as? Bool ?? true { didSet { Self.ud.set(trEN, forKey: "trEN"); send(["tr_en": trEN]) } }
    @Published var trTH = ud.object(forKey: "trTH") as? Bool ?? true { didSet { Self.ud.set(trTH, forKey: "trTH"); send(["tr_th": trTH]) } }
    @Published var polite = ud.string(forKey: "polite") ?? "krub" { didSet { Self.ud.set(polite, forKey: "polite"); send(["polite": polite]) } }
    @Published var model = EngineModel.initialModel() { didSet { Self.ud.set(model, forKey: "model"); scheduleRestart() } }
    @Published var lang = ud.string(forKey: "lang") ?? "auto" { didSet { Self.ud.set(lang, forKey: "lang"); send(["lang": lang]) } }

    // Stimme und Audio (live)
    @Published var rate = ud.object(forKey: "rate") as? Int ?? 0 { didSet { Self.ud.set(rate, forKey: "rate"); push(["rate": rate]) } }
    @Published var volume = ud.object(forKey: "volume") as? Double ?? 1.0 { didSet { Self.ud.set(volume, forKey: "volume"); push(["volume": volume]) } }
    @Published var voiceEN = ud.string(forKey: "voiceEN") ?? "" { didSet { Self.ud.set(voiceEN, forKey: "voiceEN"); push(["voice_en": voiceEN]) } }
    @Published var voiceTH = ud.string(forKey: "voiceTH") ?? "" { didSet { Self.ud.set(voiceTH, forKey: "voiceTH"); push(["voice_th": voiceTH]) } }
    @Published var silence = ud.object(forKey: "silence") as? Double ?? 0.8 { didSet { Self.ud.set(silence, forKey: "silence"); send(["silence": silence]) } }
    @Published var sensitivity = ud.string(forKey: "sensitivity") ?? "normal" { didSet { Self.ud.set(sensitivity, forKey: "sensitivity"); send(["sensitivity": sensitivity]) } }
    @Published var earcons = ud.bool(forKey: "earcons") { didSet { Self.ud.set(earcons, forKey: "earcons"); send(["earcons": earcons]) } }
    @Published var llmStyle = ud.string(forKey: "llmStyle") ?? "casual" { didSet { Self.ud.set(llmStyle, forKey: "llmStyle"); send(["style": llmStyle]) } }
    /// Geschätzte Claude-Kosten dieser Sitzung in US-Dollar (nach Preisliste, von der Engine gezählt).
    @Published private(set) var llmCostUSD = 0.0
    /// Eigene Wörter/Namen für die Claude-Übersetzung (eine Zeile: `Wort => Übersetzung` oder nur `Name`).
    static let glossaryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Dolmetscher/glossary.txt")
    @Published var glossary = (try? String(contentsOf: EngineModel.glossaryURL, encoding: .utf8)) ?? "" {
        didSet {
            try? FileManager.default.createDirectory(at: Self.glossaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? glossary.write(to: Self.glossaryURL, atomically: true, encoding: .utf8)
            send(["glossary": glossary])
        }
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
    @Published var mic = ud.string(forKey: "mic") ?? "" { didSet { Self.ud.set(mic, forKey: "mic"); scheduleRestart() } }
    @Published var denoise = ud.bool(forKey: "denoise") { didSet { Self.ud.set(denoise, forKey: "denoise"); scheduleRestart() } }
    @Published var logText = ud.bool(forKey: "logText") { didSet { Self.ud.set(logText, forKey: "logText"); scheduleRestart() } }
    /// Wird nach dem Speichern/Löschen des API-Schlüssels erhöht (Engine liest ihn nur beim Start).
    @Published var keyVersion = 0 { didSet { scheduleRestart() } }
    @Published var pushToTalk = ud.bool(forKey: "pushToTalk") {
        didSet { Self.ud.set(pushToTalk, forKey: "pushToTalk"); if running { setPaused(pushToTalk) } }
    }

    // Nur Stimmen, die schnell antworten (gemessen: erster Ton nach 0,4–0,7 s). Die Multilingual-Stimmen
    // brauchen 1,5–4 s und stehen deshalb nicht mehr zur Wahl; eine gespeicherte Auswahl bleibt gültig.
    static let voicesEN = ["en-US-AriaNeural", "en-US-JennyNeural", "en-US-MichelleNeural", "en-US-AvaNeural",
                           "en-US-EmmaNeural", "en-US-GuyNeural", "en-US-AndrewNeural", "en-US-BrianNeural",
                           "en-GB-RyanNeural"]
    static let voicesTH = ["th-TH-NiwatNeural", "th-TH-PremwadeeNeural"]
    private static let maleVoices: Set<String> = ["Guy", "Andrew", "Brian", "Ryan", "Niwat", "Christopher", "Eric"]

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
    static let llmModels = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]

    /// Einstellungen, die nur beim Start gelesen werden – Vergleich mit dem Stand beim Start.
    private var restartSignature: String {
        "\(model)|\(mic)|\(denoise)|\(llmModel)|\(logText)|\(keyVersion)"
    }
    @Published private var launchedSignature: String?
    var needsRestart: Bool { state != .stopped && launchedSignature != nil && launchedSignature != restartSignature }

    private var proc: Process?
    private var launchedAt = Date.distantPast
    private var restartWork: DispatchWorkItem?
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

    /// Einstellung mit Neustart geändert: kurz warten (mehrere Änderungen bündeln), dann neu starten.
    private func scheduleRestart() {
        restartWork?.cancel(); restartWork = nil
        guard state != .stopped else { return }
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restartWork = nil
                if self.needsRestart { self.restart() }
            }
        }
        restartWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    override init() {
        super.init()
        // Stimmprofil angelegt/gelöscht: laufende Engine lädt die Profile neu (kein Neustart nötig)
        NotificationCenter.default.addObserver(forName: .profilesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.send(["reload_profiles": true])
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

    /// Einstellung live an die laufende Engine schicken (eine JSON-Zeile auf stdin).
    func send(_ d: [String: Any]) {
        guard running, let h = stdin?.fileHandleForWriting,
              var data = try? JSONSerialization.data(withJSONObject: d) else { return }
        data.append(0x0A)
        try? h.write(contentsOf: data)
    }

    /// Einmalige Umstellung alter Installationen von "small" auf das genauere "medium".
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
        startEngine()
    }

    /// Start/Stopp-Knopf, Menüleiste, ⌃⌥D.
    func toggle() { active ? stopListening() : startListening() }

    /// Zuhören einschalten. Lädt die Engine noch, wird der Wunsch gemerkt und bei `ready` gesendet.
    func startListening() {
        guard !micLent else { return }   // Stimmprofil-Assistent nimmt gerade auf
        crashLog = nil
        wantListen = true
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            status = L.t("starting")
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard self.wantListen else { return }   // inzwischen Stopp gedrückt
                        if ok { self.startListening() } else { self.wantListen = false; self.status = L.t("nomic") }
                    }
                }
            }
            return
        default:
            wantListen = false
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
        if canListen { send(["listen": false]) }
        pttWork?.cancel(); pttWork = nil; pttHolding = false
        meter.reset()
        status = restingStatus
    }

    /// Prozess neu starten; danach wieder im vorigen Zuhör-Zustand.
    func restart() {
        let want = wantListen || micOn || (state == .stopped && listenBeforeCrash)
        stopProcess()
        listenBeforeCrash = false
        if want && !micLent { startListening() } else { startEngine() }
    }

    /// Beim Beenden der App.
    func shutdown() { stopProcess() }

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
        var args = ["-u", script, "--json", "--idle", "--model", model, "--polite", polite, "--lang", lang, "--meter",
                    "--rate", String(rate), "--volume", Self.f2(volume),
                    "--silence", Self.f2(silence), "--sensitivity", sensitivity,
                    "--llm-model", llmModel, "--style", llmStyle, logText ? "--log-text" : "--no-log-text",
                    "--tts-race", Self.f2(ttsRace)]
        args.append(fastEndpoint ? "--fast-endpoint" : "--no-fast-endpoint")   // Engine-Standard ist aus
        if !twoPerson { args.append("--no-two-person") }
        args.append(partialText ? "--partial" : "--no-partial")   // Engine-Standard ist aus
        if !speak { args.append("--mute") }
        if !trEN { args.append("--no-en") }
        if !trTH { args.append("--no-th") }
        if !mic.isEmpty { args += ["--mic", mic] }
        if denoise { args.append("--denoise") }
        if !voiceEN.isEmpty { args += ["--voice-en", voiceEN] }
        if !voiceTH.isEmpty { args += ["--voice-th", voiceTH] }
        if llm { args.append("--llm") }
        if earcons { args.append("--earcons") }
        return args
    }

    /// Prozess im Leerlauf starten (`--idle`): Modelle laden, Mikrofon bleibt aus.
    private func startEngine() {
        guard state == .stopped else { return }
        restartWork?.cancel(); restartWork = nil
        guard let script = Bundle.main.path(forResource: "dolmetscher", ofType: "py") else {
            status = "dolmetscher.py fehlt im App-Bundle"; wantListen = false; return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.python)
        p.arguments = launchArgs(script)
        p.environment = Paths.engineEnvironment()

        let out = Pipe()
        p.standardOutput = out
        let inp = Pipe()
        p.standardInput = inp
        try? FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        p.standardError = (try? FileHandle(forWritingTo: Self.logURL)) ?? FileHandle.nullDevice
        buffer = Data()
        resetRuntime()
        // Alles über die serielle Main-Queue: Ereignisse kommen in Reihenfolge an,
        // und das Prozessende überholt die letzten Zeilen nicht.
        out.fileHandleForReading.readabilityHandler = { [weak self, weak p] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let p, self.proc === p else { return }
                    self.consume(d)
                }
            }
        }
        p.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.proc === ended else { return }   // nur der aktuelle Prozess, nicht nach Stopp
                    self.engineEnded(code: ended.terminationStatus)
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
            if pushToTalk { setPaused(true) }   // kein Startargument dafür – direkt per stdin
        } catch {
            state = .stopped; wantListen = false
            status = "Start fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Unerwartetes Ende: einmal automatisch neu starten, wenn die Engine schon länger lief
    /// (im vorigen Zuhör-Zustand). `listen: false` beendet den Prozess nicht – kommt hier also nicht an.
    private func engineEnded(code: Int32) {
        let uptime = Date().timeIntervalSince(launchedAt)
        let want = wantListen || micOn
        state = .stopped; proc = nil; stdin = nil; launchedSignature = nil
        engineReady = false; micOn = false; micKnown = false
        resetRuntime()
        if code != 0 && uptime > 30 {
            wantListen = want
            startEngine()
            status = L.t("auto_restart")
            return
        }
        wantListen = false
        listenBeforeCrash = want
        status = L.t("crashed") + " (Code \(code))"
        crashLog = Self.logTail()
    }

    /// Laufzeitzustand zurücksetzen (Start, Stopp, Absturz) – sonst bleibt z. B. „busy“ hängen.
    private func resetRuntime() {
        pendingIDs.removeAll(); speakingIDs.removeAll()
        items.removeAll { $0.pending }
        backlogSTT = 0; backlogTTS = 0
        netDown.removeAll()
        llmActive = false
        llmCostUSD = 0
        meter.reset()
        pttWork?.cancel(); pttWork = nil
        for w in hearingTimers.values { w.cancel() }
        hearingTimers.removeAll()
    }

    /// Prozess beenden (Neustart, App-Ende). Der Zuhör-Wunsch bleibt – `restart()` braucht ihn.
    private func stopProcess() {
        let p = proc
        proc = nil          // vor terminate(): der terminationHandler erkennt so einen gewollten Stopp
        stdin = nil
        if let p {
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            p.terminate()
        }
        restartWork?.cancel(); restartWork = nil
        state = .stopped
        engineReady = false; micOn = false; micKnown = false
        launchedSignature = nil
        replayPausedEngine = false
        resumeWork?.cancel(); resumeWork = nil
        buffer = Data()
        resetRuntime()
        status = L.t("stopped")
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

    static func logTail(_ n: Int = 25) -> String {
        guard let d = try? Data(contentsOf: logURL) else { return "(stderr.log nicht lesbar)" }
        let s = String(decoding: d, as: UTF8.self)
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("experimental") }   // MPS-Warnung von PyTorch, kein Fehler
            .suffix(n)
        let t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "(stderr.log ist leer)" : t
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let ev = obj["event"] as? String else { continue }
            handle(ev, obj)
        }
    }

    private static var pausedText: String { L.t("paused") }

    /// Status nach dem Ende einer Ausgabe bzw. wenn nichts vorgelesen wird.
    private var idleStatus: String {
        if !micOn { return restingStatus }   // späte Ereignisse nach `listen: false` zeigen nicht „Hört zu“
        if paused { return pushToTalk ? "⏸ " + L.t("hold_to_talk") : Self.pausedText }
        return busy ? L.t("thinking") : L.t("listening")
    }

    private func index(of uid: String?) -> Int? {
        guard let uid else { return nil }
        return items.lastIndex { $0.uid == uid }
    }

    private func handle(_ ev: String, _ o: [String: Any]) {
        let id = o["id"] as? String
        switch ev {
        case "loading":   // Engine meldet, welches Modell gerade lädt (z. B. "Lade Thai-Modell …")
            let msg = o["msg"] as? String ?? ""
            status = L.t("loading") + (msg.contains("Thai") ? " (ไทย)" : msg.contains("turbo") ? " (EN+)" : "")
                + (wantListen ? " " + L.t("then_start") : "")
        case "ready":
            engineReady = true
            llmActive = o["llm"] as? Bool ?? false
            if pushToTalk && !pttHolding { setPaused(true) }
            if wantListen && !micLent {
                if canListen { send(["listen": true]) }   // sonst beim ersten `mic`-Ereignis
                status = L.t("starting")
            } else {
                wantListen = false
                status = restingStatus
            }
        case "mic":
            let on = o["on"] as? Bool ?? false
            let first = !micKnown
            micKnown = true
            micOn = on
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
            if let i = index(of: id), items[i].pending, !text.isEmpty {
                items[i].partial = text
                if let l = o["lang"] as? String { items[i].lang = l }
            }
        case "thinking":
            let key = id ?? "?"
            pendingIDs.insert(key)
            if let id {
                cancelHearingTimer(id)
                if index(of: id) == nil { items.append(.placeholder(id)) }
            }
            if !speakingNow { status = L.t("thinking") }
        case "speaking":
            let key = id ?? "?"
            speakingIDs.insert(key)
            if let i = index(of: id) {
                if let f = o["first_s"] as? Double { items[i].firstSound = f }
                if let lat = (o["latency_s"] as? NSNumber)?.doubleValue {
                    items[i].latency = lat
                    if items[i].source == nil || items[i].source == "mic" { recordLatency(lat) }
                }
            }
            status = L.t("speaking")
        case "speak_done":
            speakingIDs.remove(id ?? "?")
            if o["skipped"] as? Bool == true, let i = index(of: id) { items[i].skipped = true }
            if !speakingNow { status = idleStatus }
        case "queue":
            backlogSTT = o["stt"] as? Int ?? 0
            backlogTTS = o["tts"] as? Int ?? 0
        case "level":
            meter.rms = min(1, max(0, o["rms"] as? Double ?? 0))
            meter.voice = o["voice"] as? Bool ?? false
            if meter.voice { lastVoiceAt = Date() }
        case "net":
            let what = o["what"] as? String ?? "translate"
            if o["ok"] as? Bool ?? true { netDown.remove(what) } else { netDown.insert(what) }
        case "error": status = "⚠️ " + (o["msg"] as? String ?? "Fehler")
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
            if speakingNow { break }
            status = paused ? Self.pausedText : L.t("dropped")
        case "utt": addUtterance(o, id: id)
        case "llm_cost": llmCostUSD = (o["usd"] as? NSNumber)?.doubleValue ?? llmCostUSD
        default: break
        }
    }

    private func applyCommand(_ o: [String: Any]) {
        applyingRemote = true
        defer { applyingRemote = false }
        if o["clear"] as? Bool == true { items.removeAll() }
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
        status = paused ? Self.pausedText : "🗣 " + (reply.isEmpty ? "Wiederhole …" : reply)
    }

    private func addUtterance(_ o: [String: Any], id: String?) {
        let l = o["lang"] as? String ?? "en"
        let translated = o["translated"] as? Bool ?? true
        var u = Utterance(uid: id, translated: translated, speaker: o["speaker"] as? String, lang: l,
                          to: o["to"] as? String ?? (translated ? (l == "en" ? "th" : "en") : l),
                          text: o["text"] as? String ?? "", out: o["out"] as? String ?? "",
                          stt: o["stt"] as? Double ?? 0, tr: o["tr"] as? Double ?? 0,
                          lp: o["lp"] as? Double, provider: o["provider"] as? String,
                          source: o["source"] as? String,
                          textLatin: o["text_latin"] as? String, outLatin: o["out_latin"] as? String)
        u.readyS = (o["ready_s"] as? NSNumber)?.doubleValue
        u.alts = (o["alts"] as? [String]) ?? []
        u.numWarn = o["num_warn"] as? Bool ?? false
        u.role = o["role"] as? String
        if let id { cancelHearingTimer(id); pendingIDs.remove(id) } else { pendingIDs.remove("?") }
        if let old = o["replaces"] as? String, let i = index(of: old) {
            items[i] = u
            if let id { items.removeAll { $0.pending && $0.uid == id } }
        } else if let id, let i = items.lastIndex(where: { $0.pending && $0.uid == id }) {
            items[i] = u
        } else {
            items.append(u)
        }
    }

    // MARK: Platzhalter mit Teiltext

    /// Platzhalter je `hearing`-id: Läuft nach 3 s ohne weiteres Ereignis ab (z. B. `dropped` ohne id, „zu kurz“).
    private var hearingTimers: [String: DispatchWorkItem] = [:]
    private var lastVoiceAt = Date.distantPast

    /// Platzhalter für `id` anlegen (falls nötig) und die 3-s-Frist neu starten.
    private func touchPlaceholder(_ id: String) {
        if index(of: id) == nil { items.append(.placeholder(id)) }
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

    func say(_ text: String, lang: String = "en") {
        send(["say": ["text": text, "lang": lang]])
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

    // MARK: Push-to-Talk

    private var pttWork: DispatchWorkItem?
    @Published private(set) var pttHolding = false

    func pttDown() {
        guard running, micOn, !pttHolding else { return }
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

    // MARK: Wiedergabe einer Sprechblase (lokal, ohne Engine)

    private let synth = AVSpeechSynthesizer()
    @Published private(set) var replayingID: UUID?
    /// true, wenn *wir* die Engine fürs Vorlesen pausiert haben (damit sie die Wiedergabe nicht erneut übersetzt).
    private var replayPausedEngine = false
    /// Verzögertes Fortsetzen: Die Engine prüft die Pause erst nach der Erkennung eines ganzen
    /// Abschnitts – sofort fortsetzen würde das Echo der Wiedergabe doch noch übersetzen.
    private var resumeWork: DispatchWorkItem?

    func replay(_ u: Utterance) {
        guard !u.pending else { return }
        synth.delegate = self
        resumeWork?.cancel(); resumeWork = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let s = AVSpeechUtterance(string: u.out)
        s.voice = AVSpeechSynthesisVoice(language: u.to == "th" ? "th-TH" : "en-US")
        s.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        if running && micOn && !paused && !replayPausedEngine {
            send(["paused": true]); replayPausedEngine = true
        }
        replayingID = u.id
        synth.speak(s)
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

    // MARK: Export

    func transcript(markdown: Bool) -> String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        let day = DateFormatter(); day.dateStyle = .long; day.timeStyle = .short
        var s = markdown ? "# Dolmetscher EN ⇄ TH – \(day.string(from: Date()))\n\n"
                         : "Dolmetscher EN ⇄ TH – \(day.string(from: Date()))\n\n"
        for u in items where !u.pending {
            let who = u.lang == "en" ? "🇬🇧 EN" : "🇹🇭 TH"
            let arrow = u.translated ? (u.to == "th" ? "🇹🇭 TH" : "🇬🇧 EN") : "(nicht übersetzt)"
            if markdown {
                s += "**\(df.string(from: u.date)) · \(who)**: \(u.text)  \n"
                if u.translated { s += "→ \(arrow): \(u.out)\n\n" } else { s += "\n" }
            } else {
                s += "[\(df.string(from: u.date))] \(who): \(u.text)\n"
                if u.translated { s += "  → \(arrow): \(u.out)\n" }
                s += "\n"
            }
        }
        return s
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
