// Model.swift – Zustand der App: Zuhören, Sprachwahl, Befehle, Übersetzen, Vorlesen, Verlauf.
import AVFoundation
import Observation
import SwiftUI

struct Entry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var src: Lang
    var text: String
    var translation: String?
    var error: String?
    /// Was der Erkenner der anderen Sprache gehört hat – für „andere Sprache war gemeint“.
    var alt: String?
    var provider: String?
}

@MainActor @Observable
final class InterpreterModel {
    enum Phase: Equatable { case idle, loading, listening, failed(String) }
    enum Mode: String, CaseIterable { case auto, en, th
        var langs: [Lang] { self == .auto ? [.en, .th] : [self == .en ? .en : .th] }
    }

    var phase: Phase = .idle
    var paused = false
    var entries: [Entry] = []
    var partial = ""
    var level: Float = 0
    var hearing = false
    var speakingID: UUID?
    var notice: String?
    var showHelp = false
    var offlineReady = false
    /// Solange ein Sprachmodell geladen wird: Sprache und Fortschritt 0…1.
    var download: (lang: Lang, fraction: Double)?

    var mode: Mode { didSet { save("mode", mode.rawValue); if phase == .listening { restart() } } }
    var pauseSeconds: Double { didSet { save("pauseSeconds", pauseSeconds); engine?.setPause(pauseSeconds) } }
    var rate: Double { didSet { save("rate", rate) } }
    var volume: Double { didSet { save("volume", volume) } }
    var allowOnline: Bool { didSet { save("allowOnline", allowOnline) } }
    var autoSpeak: Bool { didSet { save("autoSpeak", autoSpeak) } }
    var uiLang: String { didSet { save("uiLang", uiLang); L10n.lang = uiLang } }

    @ObservationIgnored private var engine: (any SpeechEngine)?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var speakChain: Task<Void, Never>?
    @ObservationIgnored private var pendingSpeech = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var speechGeneration = 0
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var awakeUntil = Date.distantPast
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let translator = Translator()
    @ObservationIgnored private let speaker = Speaker()
    @ObservationIgnored private let d = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        mode = Mode(rawValue: d.string(forKey: "mode") ?? "") ?? .auto
        pauseSeconds = d.object(forKey: "pauseSeconds") as? Double ?? 0.8
        rate = d.object(forKey: "rate") as? Double ?? 1.0
        volume = d.object(forKey: "volume") as? Double ?? 1.0
        allowOnline = d.object(forKey: "allowOnline") as? Bool ?? true
        autoSpeak = d.object(forKey: "autoSpeak") as? Bool ?? true
        uiLang = d.string(forKey: "uiLang") ?? L10n.systemLang()
        L10n.lang = uiLang
        entries = Self.loadHistory()
        Task { await refreshOffline() }
    }

    private func save(_ key: String, _ value: Any) { d.set(value, forKey: key) }

    var isBusy: Bool { phase == .loading }
    var isListening: Bool { phase == .listening }

    func refreshOffline() async {
        let a = await Translator.offlineInstalled(from: .en)
        let b = await Translator.offlineInstalled(from: .th)
        offlineReady = a && b
    }

    // MARK: Zuhören

    func toggle() { phase == .listening || phase == .loading ? stop() : start() }

    func start() {
        guard !isBusy, !isListening else { return }
        phase = .loading
        paused = false
        generation += 1
        let mine = generation
        let e = AppleSpeechEngine()
        let pendingStop = stopTask
        Task {
            await pendingStop?.value   // die alte Aufnahme muss die Audio-Session erst freigeben
            do {
                try await e.start(langs: mode.langs, pauseSeconds: pauseSeconds) { lang, f in
                    Task { @MainActor [weak self] in
                        if let self, self.generation == mine, self.phase == .loading { self.download = f < 1 ? (lang, f) : nil }
                    }
                }
                download = nil
                guard generation == mine else { await e.stop(); return }   // inzwischen abgebrochen
                engine = e
                phase = .listening
                UIApplication.shared.isIdleTimerDisabled = true
                listenTask = Task { [weak self] in
                    for await ev in e.events { self?.handle(ev) }
                }
            } catch {
                await e.stop()
                if generation == mine { download = nil; phase = .failed(error.localizedDescription) }
            }
        }
    }

    func stop() {
        generation += 1
        download = nil
        guard let e = engine else { phase = .idle; return }
        engine = nil
        listenTask?.cancel()
        stopSpeaking()
        phase = .idle
        partial = ""; level = 0; hearing = false
        UIApplication.shared.isIdleTimerDisabled = false
        stopTask = Task { await e.stop() }
    }

    private func restart() {
        stop()
        start()
    }

    private func handle(_ ev: SpeechEvent) {
        switch ev {
        case .level(let l): level = l
        case .hearing(let h): hearing = h; if !h { partial = "" }
        case .partial(let en, let th):
            guard !paused else { return }
            let pick = LanguagePick.pick(en: Hypothesis(text: en, confidence: 0.5), th: Hypothesis(text: th, confidence: 0.5))
            partial = pick == .th ? th : en
        case .utterance(let en, let th): heard(en: en, th: th)
        case .interrupted: if phase == .listening { restart() }
        }
    }

    private func heard(en: Hypothesis?, th: Hypothesis?) {
        partial = ""
        guard let lang = LanguagePick.pick(en: en, th: th) else { return }
        if lang == .en, let text = en?.text, let cmd = Commands.detect(text, awake: Date() < awakeUntil) {
            run(cmd)
            return
        }
        guard !paused else { return }
        let text = (lang == .en ? en : th)?.text ?? ""
        let alt = (lang == .en ? th : en)?.text
        add(Entry(src: lang, text: text, alt: alt))
    }

    // MARK: Befehle

    func run(_ cmd: VoiceCommand) {
        awakeUntil = cmd == .wake ? Date().addingTimeInterval(6) : .distantPast
        switch cmd {
        case .wake: flash("👂 " + T("say_command"))
        case .pause: paused = true; stopSpeaking(); flash("⏸ " + T("paused"))
        case .resume: paused = false; flash("▶️ " + T("resumed"))
        case .repeat: if let last = entries.last(where: { $0.translation != nil }) { speak(last) }
        case .slower: rate = max(0.5, rate - 0.15); flash("🐢 " + T("cmd_slower_done"))
        case .faster: rate = min(1.5, rate + 0.15); flash("🐇 " + T("cmd_faster_done"))
        case .louder: volume = min(1, volume + 0.25); flash("🔊 " + T("cmd_louder_done"))
        case .quieter: volume = max(0.25, volume - 0.25); flash("🔉 " + T("cmd_quieter_done"))
        case .clear: clear()
        case .help: showHelp = true
        }
    }

    private func flash(_ s: String) {
        notice = s
        noticeTask?.cancel()
        noticeTask = Task { try? await Task.sleep(for: .seconds(2.5)); if !Task.isCancelled { notice = nil } }
    }

    // MARK: Übersetzen

    /// Getippter Satz oder Schnellsatz.
    func submit(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        add(Entry(src: LanguagePick.ofTyped(text), text: text))
    }

    private func add(_ e: Entry) {
        entries.append(e)
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
        translate(e.id)
    }

    private func translate(_ id: UUID) {
        guard let e = entries.first(where: { $0.id == id }) else { return }
        Task {
            do {
                let r = try await translator.translate(e.text, from: e.src, allowOnline: allowOnline)
                update(id) { $0.translation = r.text; $0.provider = r.provider; $0.error = nil }
                if autoSpeak, let done = entries.first(where: { $0.id == id }) { speak(done) }
            } catch {
                update(id) { $0.error = error.localizedDescription }
            }
            persist()
        }
    }

    private func update(_ id: UUID, _ change: (inout Entry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[i])
    }

    /// Die App hat die falsche Sprache gewählt: mit dem Ergebnis des anderen Erkenners neu übersetzen.
    func swapLanguage(_ id: UUID) {
        guard let e = entries.first(where: { $0.id == id }), let alt = e.alt, !alt.isEmpty else { return }
        stopSpeaking()
        update(id) { $0.alt = e.text; $0.text = alt; $0.src = e.src.other; $0.translation = nil; $0.error = nil }
        translate(id)
    }

    func retry(_ id: UUID) {
        update(id) { $0.error = nil }
        translate(id)
    }

    func clear() {
        stopSpeaking()
        entries.removeAll()
        persist()
    }

    // MARK: Vorlesen (nacheinander; währenddessen hört das Mikrofon weg)

    func speak(_ e: Entry) {
        guard let text = e.translation, !text.isEmpty else { return }
        let lang = e.src.other, id = e.id
        let prev = speakChain
        pendingSpeech += 1
        let gen = speechGeneration
        speakChain = Task {
            await prev?.value
            guard gen == speechGeneration else {   // inzwischen gestoppt: Warteschlange verfällt
                pendingSpeech -= 1
                if pendingSpeech == 0 { engine?.setMuted(false) }
                return
            }
            engine?.setMuted(true)
            if engine == nil {
                try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            speakingID = id
            await speaker.speak(text, lang: lang, rate: rate, volume: volume)
            if speakingID == id { speakingID = nil }
            pendingSpeech -= 1
            if pendingSpeech == 0 {
                try? await Task.sleep(for: .milliseconds(400))   // Nachhall nicht als Sprache werten
                if pendingSpeech == 0 { engine?.setMuted(false) }
            }
        }
    }

    /// Bricht den laufenden Satz ab und verwirft alle, die noch warten.
    func stopSpeaking() {
        speechGeneration += 1
        speaker.stop()
    }

    // MARK: Verlauf

    private static var historyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private static func loadHistory() -> [Entry] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Self.historyURL, options: [.atomic, .completeFileProtection])
        }
    }

    var transcript: String {
        entries.map { "\($0.src == .en ? "EN" : "TH"): \($0.text)\n→ \($0.translation ?? "–")" }.joined(separator: "\n\n")
    }
}
