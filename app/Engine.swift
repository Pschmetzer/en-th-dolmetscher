// Engine.swift – startet die Python-Engine (dolmetscher.py --json), liest ihre Ereignisse
// und schickt Einstellungen live als JSON-Zeilen auf stdin.
import SwiftUI
import AVFoundation

struct Utterance: Identifiable {
    let id = UUID()
    var translated = true
    let lang: String        // gesprochene Sprache
    let to: String          // Sprache von `out`
    let text: String
    let out: String
    let secs: Double
    let date = Date()
}

enum EngineState: Equatable { case stopped, starting, running }

@MainActor
final class EngineModel: NSObject, ObservableObject {
    @Published var items: [Utterance] = []
    @Published var status = "Gestoppt"
    @Published private(set) var state: EngineState = .stopped
    var running: Bool { state == .running }
    var active: Bool { state != .stopped }
    @Published var busy = false
    @Published var paused = false
    /// Gesetzt, wenn die Engine unerwartet endet: letzte Zeilen aus stderr.log.
    @Published var crashLog: String?

    private static let ud = UserDefaults.standard
    @Published var speak = ud.object(forKey: "speak") as? Bool ?? true { didSet { Self.ud.set(speak, forKey: "speak"); send(["speak": speak]) } }
    @Published var trEN = ud.object(forKey: "trEN") as? Bool ?? true { didSet { Self.ud.set(trEN, forKey: "trEN"); send(["tr_en": trEN]) } }
    @Published var trTH = ud.object(forKey: "trTH") as? Bool ?? true { didSet { Self.ud.set(trTH, forKey: "trTH"); send(["tr_th": trTH]) } }
    @Published var polite = ud.string(forKey: "polite") ?? "krub" { didSet { Self.ud.set(polite, forKey: "polite"); send(["polite": polite]) } }
    @Published var model = EngineModel.initialModel() { didSet { Self.ud.set(model, forKey: "model") } }
    @Published var lang = ud.string(forKey: "lang") ?? "auto" { didSet { Self.ud.set(lang, forKey: "lang"); send(["lang": lang]) } }

    private var proc: Process?

    override init() {
        super.init()
        // Nur für Screenshots/Tests: DOLMETSCHER_DEMO=1 füllt den Verlauf mit Beispielen.
        if ProcessInfo.processInfo.environment["DOLMETSCHER_DEMO"] != nil {
            items = [
                Utterance(lang: "en", to: "th", text: "Good morning! Did you get the samples?", out: "สวัสดีตอนเช้าครับ ได้รับตัวอย่างแล้วหรือยังครับ", secs: 1.2),
                Utterance(lang: "th", to: "en", text: "ได้รับแล้วค่ะ สวยมากเลย", out: "Yes, I got them. They are very beautiful.", secs: 1.4),
                Utterance(translated: false, lang: "en", to: "en", text: "OK", out: "OK", secs: 0.4),
            ]
        }
    }
    private var stdin: Pipe?
    private var buffer = Data()

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Dolmetscher/stderr.log")

    /// Einstellung live an die laufende Engine schicken (eine JSON-Zeile auf stdin).
    private func send(_ d: [String: Any]) {
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

    private func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    func toggle() { active ? stop() : start() }

    func start() {
        guard state == .stopped else { return }   // kein Doppelstart, während die Mikrofon-Abfrage offen ist
        state = .starting
        crashLog = nil
        status = "Starte …"
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.state == .starting else { return }   // inzwischen Stopp gedrückt
                    if ok { self.launch() }
                    else {
                        self.state = .stopped
                        self.status = "Kein Mikrofon-Zugriff – Systemeinstellungen → Datenschutz → Mikrofon"
                    }
                }
            }
        }
    }

    func restart() { stop(); start() }

    private func launch() {
        guard let script = Bundle.main.path(forResource: "dolmetscher", ofType: "py") else {
            state = .stopped; status = "dolmetscher.py fehlt im App-Bundle"; return
        }
        let python = info("DolmetscherPython") ?? "/usr/bin/python3"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        var args = ["-u", script, "--json", "--model", model, "--polite", polite, "--lang", lang]
        if !speak { args.append("--mute") }
        if !trEN { args.append("--no-en") }
        if !trTH { args.append("--no-th") }
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let ff = info("DolmetscherFFmpeg") { env["DOLMETSCHER_FFMPEG"] = ff }
        p.environment = env

        let out = Pipe()
        p.standardOutput = out
        let inp = Pipe()
        p.standardInput = inp
        try? FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        p.standardError = (try? FileHandle(forWritingTo: Self.logURL)) ?? FileHandle.nullDevice
        buffer = Data()
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
                    let code = ended.terminationStatus
                    self.state = .stopped; self.busy = false; self.proc = nil; self.stdin = nil
                    self.status = "Engine unerwartet beendet (Code \(code))"
                    self.crashLog = Self.logTail()
                }
            }
        }
        do {
            try p.run()
            proc = p; stdin = inp; state = .running; paused = false; status = "Starte …"
        } catch {
            state = .stopped
            status = "Start fehlgeschlagen: \(error.localizedDescription)"
        }
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
        replayPausedEngine = false
        resumeWork?.cancel(); resumeWork = nil
        buffer = Data()
        busy = false
        status = "Gestoppt"
    }

    static func logTail(_ n: Int = 25) -> String {
        guard let d = try? Data(contentsOf: logURL) else { return "(stderr.log nicht lesbar)" }
        let s = String(decoding: d, as: UTF8.self)
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).suffix(n)
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

    private static let pausedText = "⏸ Pausiert – sag „Translator, resume“"

    private func handle(_ ev: String, _ o: [String: Any]) {
        switch ev {
        case "loading": status = "Lade Sprachmodell …"
        case "ready": status = "Modell geladen (" + (o["device"] as? String == "mps" ? "Apple-GPU" : "CPU") + ")"
        case "listening":
            status = paused ? Self.pausedText : "🎙 Hört zu – einfach Englisch oder Thai sprechen"
            busy = false
        case "hearing": status = "👂 Höre …"
        case "thinking": status = "⏳ Übersetze …"; busy = true
        case "speaking": status = "🔊 Spricht …"
        case "error": status = "⚠️ " + (o["msg"] as? String ?? "Fehler")
        case "command":
            if o["clear"] as? Bool == true { items.removeAll() }
            if let l = o["lang"] as? String { lang = l }
            if let p = o["polite"] as? String { polite = p }
            if let v = o["tr_en"] as? Bool, v != trEN { trEN = v }
            if let v = o["tr_th"] as? Bool, v != trTH { trTH = v }
            paused = o["paused"] as? Bool ?? false
            replayPausedEngine = false   // Nutzer hat selbst pausiert/fortgesetzt
            resumeWork?.cancel(); resumeWork = nil
            let reply = o["reply"] as? String ?? ""
            status = paused ? Self.pausedText : "🗣 " + (reply.isEmpty ? "Wiederhole …" : reply)
        case "dropped" where replayPausedEngine:
            busy = false   // Echo der eigenen Wiedergabe verworfen – Status nicht ändern
        case "dropped" where paused:
            status = Self.pausedText; busy = false
        case "dropped": status = "🤷 " + (o["reason"] as? String ?? "nicht verstanden") + " – bitte lauter/länger sprechen"; busy = false
        case "utt":
            let secs = (o["stt"] as? Double ?? 0) + (o["tr"] as? Double ?? 0)
            let l = o["lang"] as? String ?? "en"
            let translated = o["translated"] as? Bool ?? true
            items.append(Utterance(translated: translated, lang: l,
                                   to: o["to"] as? String ?? (translated ? (l == "en" ? "th" : "en") : l),
                                   text: o["text"] as? String ?? "",
                                   out: o["out"] as? String ?? "", secs: secs))
        default: break
        }
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
        for u in items {
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
