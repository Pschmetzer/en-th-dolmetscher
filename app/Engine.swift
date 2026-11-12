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

struct Utterance: Identifiable {
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
    var lp: Double?              // Erkennungs-Konfidenz (log-prob)
    var provider: String?
    var source: String?
    var skipped = false          // wegen Rückstand nicht vorgelesen
    var pending = false          // Platzhalter: wird gerade erkannt/übersetzt
    let textLatin: String?
    let outLatin: String?
    var date = Date()

    init(uid: String? = nil, translated: Bool = true, speaker: String? = nil, lang: String, to: String,
         text: String, out: String, stt: Double = 0, tr: Double = 0, lp: Double? = nil,
         provider: String? = nil, source: String? = nil, skipped: Bool = false, pending: Bool = false) {
        self.uid = uid; self.translated = translated; self.speaker = speaker
        self.lang = lang; self.to = to; self.text = text; self.out = out
        self.stt = stt; self.tr = tr; self.lp = lp; self.provider = provider; self.source = source
        self.skipped = skipped; self.pending = pending
        self.textLatin = Translit.latin(text)
        self.outLatin = translated ? Translit.latin(out) : nil
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

enum EngineState: Equatable { case stopped, starting, running }

@MainActor
final class EngineModel: NSObject, ObservableObject {
    @Published var items: [Utterance] = []
    @Published var status = L.t("stopped")
    @Published private(set) var state: EngineState = .stopped
    var running: Bool { state == .running }
    var active: Bool { state != .stopped }
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
    @Published var model = EngineModel.initialModel() { didSet { Self.ud.set(model, forKey: "model") } }
    @Published var lang = ud.string(forKey: "lang") ?? "auto" { didSet { Self.ud.set(lang, forKey: "lang"); send(["lang": lang]) } }

    // Stimme und Audio (live)
    @Published var rate = ud.object(forKey: "rate") as? Int ?? 0 { didSet { Self.ud.set(rate, forKey: "rate"); push(["rate": rate]) } }
    @Published var volume = ud.object(forKey: "volume") as? Double ?? 1.0 { didSet { Self.ud.set(volume, forKey: "volume"); push(["volume": volume]) } }
    @Published var voiceEN = ud.string(forKey: "voiceEN") ?? "" { didSet { Self.ud.set(voiceEN, forKey: "voiceEN"); push(["voice_en": voiceEN]) } }
    @Published var voiceTH = ud.string(forKey: "voiceTH") ?? "" { didSet { Self.ud.set(voiceTH, forKey: "voiceTH"); push(["voice_th": voiceTH]) } }
    @Published var silence = ud.object(forKey: "silence") as? Double ?? 0.8 { didSet { Self.ud.set(silence, forKey: "silence"); send(["silence": silence]) } }
    @Published var sensitivity = ud.string(forKey: "sensitivity") ?? "normal" { didSet { Self.ud.set(sensitivity, forKey: "sensitivity"); send(["sensitivity": sensitivity]) } }
    @Published var earcons = ud.bool(forKey: "earcons") { didSet { Self.ud.set(earcons, forKey: "earcons"); send(["earcons": earcons]) } }
    @Published var llm = ud.bool(forKey: "llm") { didSet { Self.ud.set(llm, forKey: "llm"); send(["llm": llm]) } }
    // Nur beim Start wirksam (Neustart nötig)
    @Published var llmModel = ud.string(forKey: "llmModel") ?? "claude-opus-5-5" { didSet { Self.ud.set(llmModel, forKey: "llmModel") } }
    @Published var mic = ud.string(forKey: "mic") ?? "" { didSet { Self.ud.set(mic, forKey: "mic") } }
    @Published var denoise = ud.bool(forKey: "denoise") { didSet { Self.ud.set(denoise, forKey: "denoise") } }
    @Published var logText = ud.bool(forKey: "logText") { didSet { Self.ud.set(logText, forKey: "logText") } }
    /// Wird nach dem Speichern/Löschen des API-Schlüssels erhöht (Engine liest ihn nur beim Start).
    @Published var keyVersion = 0
    @Published var pushToTalk = ud.bool(forKey: "pushToTalk") {
        didSet { Self.ud.set(pushToTalk, forKey: "pushToTalk"); if running { setPaused(pushToTalk) } }
    }

    static let voicesEN = ["en-US-AvaMultilingualNeural", "en-US-AndrewMultilingualNeural",
                           "en-GB-SoniaNeural", "en-US-EmmaMultilingualNeural"]
    static let voicesTH = ["th-TH-NiwatNeural", "th-TH-PremwadeeNeural", "th-TH-AcharaNeural"]
    static let llmModels = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]

    /// Einstellungen, die nur beim Start gelesen werden – Vergleich mit dem Stand beim Start.
    private var restartSignature: String {
        "\(model)|\(mic)|\(denoise)|\(llmModel)|\(logText)|\(keyVersion)"
    }
    @Published private var launchedSignature: String?
    var needsRestart: Bool { active && launchedSignature != nil && launchedSignature != restartSignature }

    private var proc: Process?
    private var launchedAt = Date.distantPast

    override init() {
        super.init()
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

    func toggle() { active ? stop() : start() }

    func start() {
        guard state == .stopped else { return }   // kein Doppelstart, während die Mikrofon-Abfrage offen ist
        state = .starting
        crashLog = nil
        status = L.t("starting")
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.state == .starting else { return }   // inzwischen Stopp gedrückt
                    if ok { self.launch() }
                    else {
                        self.state = .stopped
                        self.status = L.t("nomic")
                    }
                }
            }
        }
    }

    func restart() { stop(); start() }

    private static func f2(_ v: Double) -> String { String(format: "%.2f", v) }

    private func launchArgs(_ script: String) -> [String] {
        var args = ["-u", script, "--json", "--model", model, "--polite", polite, "--lang", lang, "--meter",
                    "--rate", String(rate), "--volume", Self.f2(volume),
                    "--silence", Self.f2(silence), "--sensitivity", sensitivity,
                    "--llm-model", llmModel, logText ? "--log-text" : "--no-log-text"]
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

    private func launch() {
        guard let script = Bundle.main.path(forResource: "dolmetscher", ofType: "py") else {
            state = .stopped; status = "dolmetscher.py fehlt im App-Bundle"; return
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
            proc = p; stdin = inp; state = .running; paused = false; status = L.t("starting")
            launchedAt = Date()
            launchedSignature = restartSignature
            if pushToTalk { setPaused(true) }   // kein Startargument dafür – direkt per stdin
        } catch {
            state = .stopped
            status = "Start fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Unerwartetes Ende: einmal automatisch neu starten, wenn die Engine schon länger lief.
    private func engineEnded(code: Int32) {
        let uptime = Date().timeIntervalSince(launchedAt)
        state = .stopped; proc = nil; stdin = nil; launchedSignature = nil
        resetRuntime()
        if code != 0 && uptime > 30 {
            start()
            status = L.t("auto_restart")
            return
        }
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
        meter.reset()
        pttWork?.cancel(); pttWork = nil
    }

    func stop() {
        let p = proc
        proc = nil          // vor terminate(): der terminationHandler erkennt so einen gewollten Stopp
        stdin = nil
        if let p {
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            p.terminate()
        }
        state = .stopped
        launchedSignature = nil
        replayPausedEngine = false
        resumeWork?.cancel(); resumeWork = nil
        buffer = Data()
        resetRuntime()
        status = L.t("stopped")
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
        paused ? Self.pausedText : (busy ? L.t("thinking") : L.t("listening"))
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
        case "ready":
            status = L.t("ready") + " (" + (o["device"] as? String == "mps" ? "Apple-GPU" : "CPU") + ")"
            llmActive = o["llm"] as? Bool ?? false
            if pushToTalk && !pttHolding { setPaused(true) }
        case "listening":   // ändert den Sprech-Status nicht
            if id == nil { pendingIDs.remove("?") }   // ältere Engine ohne ids
            if !speakingNow { status = idleStatus }
        case "hearing": if !speakingNow { status = L.t("hearing") }
        case "thinking":
            let key = id ?? "?"
            pendingIDs.insert(key)
            if let id, index(of: id) == nil { items.append(.placeholder(id)) }
            if !speakingNow { status = L.t("thinking") }
        case "speaking":
            let key = id ?? "?"
            speakingIDs.insert(key)
            if let i = index(of: id), let f = o["first_s"] as? Double { items[i].firstSound = f }
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
        case "net":
            let what = o["what"] as? String ?? "translate"
            if o["ok"] as? Bool ?? true { netDown.remove(what) } else { netDown.insert(what) }
        case "error": status = "⚠️ " + (o["msg"] as? String ?? "Fehler")
        case "command": applyCommand(o)
        case "dropped":
            if let id {
                pendingIDs.remove(id)
                items.removeAll { $0.pending && $0.uid == id }
            } else {
                pendingIDs.remove("?")
            }
            if replayPausedEngine { break }   // Echo der eigenen Wiedergabe verworfen – Status nicht ändern
            if speakingNow { break }
            status = paused ? Self.pausedText : L.t("dropped")
        case "utt": addUtterance(o, id: id)
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
        let u = Utterance(uid: id, translated: translated, speaker: o["speaker"] as? String, lang: l,
                          to: o["to"] as? String ?? (translated ? (l == "en" ? "th" : "en") : l),
                          text: o["text"] as? String ?? "", out: o["out"] as? String ?? "",
                          stt: o["stt"] as? Double ?? 0, tr: o["tr"] as? Double ?? 0,
                          lp: o["lp"] as? Double, provider: o["provider"] as? String,
                          source: o["source"] as? String)
        if let id { pendingIDs.remove(id) } else { pendingIDs.remove("?") }
        if let old = o["replaces"] as? String, let i = index(of: old) {
            items[i] = u
            if let id { items.removeAll { $0.pending && $0.uid == id } }
        } else if let id, let i = items.lastIndex(where: { $0.pending && $0.uid == id }) {
            items[i] = u
        } else {
            items.append(u)
        }
    }

    // MARK: Steuerung

    func setPaused(_ p: Bool) {
        guard running else { return }
        paused = p
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

    func retranslate(_ u: Utterance, text: String) {
        guard let uid = u.uid else { return }
        send(["retranslate": ["id": uid, "text": text, "lang": u.lang]])
    }

    // MARK: Push-to-Talk

    private var pttWork: DispatchWorkItem?
    @Published private(set) var pttHolding = false

    func pttDown() {
        guard running, !pttHolding else { return }
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
        if running && !paused && !replayPausedEngine {
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
