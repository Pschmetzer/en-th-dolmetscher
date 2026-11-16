// Model.swift – Zustand der App: Zuhören, Sprachwahl, Befehle, Übersetzen, Vorlesen, Verlauf, Satzbuch.
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
    /// "apple" (offline), "google"/"mymemory" (online), "phrasebook"
    var provider: String?
    /// Aussprache-Hilfe (nur Satzbuch)
    var roman: String?
}

enum AppSheet: String, Identifiable {
    case settings, phrasebook, photo, help, emergency, baht
    var id: String { rawValue }
}

@MainActor @Observable
final class InterpreterModel {
    static let shared = InterpreterModel()

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
    var sheet: AppSheet?
    var offlineReady = false
    /// Solange ein Sprachmodell geladen wird: Sprache und Fortschritt 0…1.
    var download: (lang: Lang, fraction: Double)?
    var favorites: [Phrase] = []
    /// Anruf o. Ä.: Aufnahme ruht, geht danach von selbst weiter.
    var interrupted = false
    /// Whisper-Modell wird geladen (beim ersten Mal bereitet Core ML es vor – das dauert).
    var whisperPreparing = false
    /// Die laufende Aufnahme nutzt Whisper.
    var usingWhisper = false

    var mode: Mode { didSet { save("mode", mode.rawValue); if phase == .listening { restart() } } }
    var pauseSeconds: Double { didSet { save("pauseSeconds", pauseSeconds); engine?.setPause(pauseSeconds) } }
    var rate: Double { didSet { save("rate", rate) } }
    var volume: Double { didSet { save("volume", volume) } }
    var allowOnline: Bool { didSet { save("allowOnline", allowOnline) } }
    var autoSpeak: Bool { didSet { save("autoSpeak", autoSpeak) } }
    var uiLang: String { didSet { save("uiLang", uiLang); L10n.lang = uiLang } }
    var politeness: Politeness { didSet { save("politeness", politeness.rawValue) } }
    var haptics: Bool { didSet { save("haptics", haptics); Haptics.enabled = haptics } }
    /// Nach so vielen Minuten ohne Sprache von selbst stoppen (0 = nie) – spart Akku.
    var autoStopMinutes: Int { didSet { save("autoStopMinutes", autoStopMinutes) } }
    /// Weiter zuhören, wenn die App im Hintergrund ist oder der Bildschirm aus.
    var background: Bool { didSet { save("background", background) } }
    /// Mikrofon eines Bluetooth-Headsets verwenden (schlechtere Tonqualität, aber näher am Mund).
    var headset: Bool { didSet { save("headset", headset); if phase == .listening { restart() } } }
    /// Verlauf aufbewahren: 0 = gar nicht speichern, sonst Tage (-1 = für immer).
    var historyDays: Int { didSet { save("historyDays", historyDays); persist() } }
    /// Thai-Ausgabe immer über den Lautsprecher, auch mit Kopfhörern (das Gegenüber soll es hören).
    var thaiOnSpeaker: Bool { didSet { save("thaiOnSpeaker", thaiOnSpeaker) } }
    var emergency: EmergencyInfo { didSet { Self.store(emergency, "emergency.json") } }

    @ObservationIgnored private var engine: (any SpeechEngine)?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var speakChain: Task<Void, Never>?
    @ObservationIgnored private var pendingSpeech = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var speechGeneration = 0
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    /// Zähler je Eintrag: eine ältere Übersetzungsanfrage darf eine neuere nicht überschreiben.
    @ObservationIgnored private var revisions: [UUID: Int] = [:]
    @ObservationIgnored private var awakeUntil = Date.distantPast
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var lastActivity = Date()
    /// Lief das Zuhören, als die App in den Hintergrund ging? Dann beim Zurückkommen weitermachen.
    @ObservationIgnored private var resumeOnForeground = false
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
        politeness = Politeness(rawValue: d.string(forKey: "politeness") ?? "") ?? .male
        haptics = d.object(forKey: "haptics") as? Bool ?? true
        autoStopMinutes = d.object(forKey: "autoStopMinutes") as? Int ?? 10
        background = d.object(forKey: "background") as? Bool ?? false
        headset = d.object(forKey: "headset") as? Bool ?? false
        historyDays = d.object(forKey: "historyDays") as? Int ?? 30
        thaiOnSpeaker = d.object(forKey: "thaiOnSpeaker") as? Bool ?? true
        emergency = Self.load(EmergencyInfo.self, "emergency.json") ?? EmergencyInfo()
        L10n.lang = uiLang
        Haptics.enabled = haptics
        entries = Self.load([Entry].self, "history.json") ?? []
        pruneHistory()
        favorites = Self.load([Phrase].self, "favorites.json") ?? []
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
        let pendingStop = stopTask
        let options = AudioOptions(headset: headset)
        let langs = mode.langs, pause = pauseSeconds
        // Whisper nur auf Wunsch und nur mit vollständigem Modell – sonst Apple mit Hinweis.
        let wantWhisper = WhisperStore.shared.enabled
        let variant = WhisperStore.shared.ready
        whisperPreparing = wantWhisper && variant != nil
        startTask = Task {
            await pendingStop?.value   // die alte Aufnahme muss die Audio-Session erst freigeben
            var note: String?
            var started: (any SpeechEngine)?
            do {
                if wantWhisper, let variant {
                    let w = WhisperSpeechEngine(variant: variant)
                    do {
                        try await w.start(langs: langs, pauseSeconds: pause, options: options) { _, _ in }
                        started = w
                    } catch let f as WhisperFailure {
                        await w.stop()
                        note = "⚠️ " + (f.errorDescription ?? "") + " – " + T("whisper_fallback")
                    } catch {
                        await w.stop()
                        throw error
                    }
                } else if wantWhisper {
                    note = "⚠️ " + T("whisper_no_model") + " – " + T("whisper_fallback")
                }
                whisperPreparing = false
                guard generation == mine else { await started?.stop(); return }   // inzwischen abgebrochen
                if started == nil {
                    let a = AppleSpeechEngine()
                    do {
                        try await a.start(langs: langs, pauseSeconds: pause, options: options) { lang, f in
                            Task { @MainActor [weak self] in
                                if let self, self.generation == mine, self.phase == .loading { self.download = f < 1 ? (lang, f) : nil }
                            }
                        }
                    } catch {
                        await a.stop()
                        throw error
                    }
                    started = a
                }
                guard let e = started else { return }
                download = nil
                guard generation == mine else { await e.stop(); return }   // inzwischen abgebrochen
                engine = e
                usingWhisper = e is WhisperSpeechEngine
                // Läuft gerade eine Ausgabe (z. B. getippter Satz), soll die neue Aufnahme sie nicht hören.
                if pendingSpeech > 0 { e.setMuted(true) }
                phase = .listening
                lastActivity = Date()
                Haptics.success()
                UIApplication.shared.isIdleTimerDisabled = true
                listenTask = Task { [weak self] in
                    for await ev in e.events { self?.handle(ev) }
                }
                watchIdle()
                if let note { flash(note, seconds: 6) }
            } catch {
                whisperPreparing = false
                if generation == mine {
                    download = nil
                    phase = .failed(error.localizedDescription)
                    Haptics.error()
                }
            }
        }
    }

    func stop() {
        generation += 1
        download = nil
        whisperPreparing = false
        usingWhisper = false
        idleTask?.cancel()
        guard let e = engine else {
            // Start läuft noch (z. B. Modell-Download): der nächste Start wartet, bis er sauber abgebrochen ist.
            if let st = startTask { stopTask = Task { await st.value } }
            phase = .idle
            return
        }
        engine = nil
        listenTask?.cancel()
        stopSpeaking()
        phase = .idle
        partial = ""; level = 0; hearing = false
        UIApplication.shared.isIdleTimerDisabled = false
        Haptics.tap()
        stopTask = Task { await e.stop() }
    }

    private func restart() {
        stop()
        start()
    }

    /// App geht in den Hintergrund: ohne Hintergrund-Einstellung aufhören zuzuhören.
    func enteredBackground() {
        guard !background else { return }
        resumeOnForeground = isListening || isBusy
        stop()
    }

    /// Zurück im Vordergrund: weitermachen, wenn vorher zugehört wurde.
    func enteredForeground() {
        if resumeOnForeground { resumeOnForeground = false; start() }
        pruneHistory()
    }

    private func pruneHistory() {
        guard historyDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(historyDays) * 86_400)
        let before = entries.count
        entries.removeAll { $0.date < cutoff }
        if entries.count != before { persist() }
    }

    private func watchIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, self.isListening, self.autoStopMinutes > 0 else { continue }
                if Date().timeIntervalSince(self.lastActivity) > Double(self.autoStopMinutes) * 60 {
                    self.stop()
                    self.flash("💤 " + T("auto_stopped"))
                    return
                }
            }
        }
    }

    private func handle(_ ev: SpeechEvent) {
        switch ev {
        case .level(let l): level = l
        case .hearing(let h):
            hearing = h
            if h { lastActivity = Date() } else { partial = "" }
        case .partial(let en, let th):
            guard !paused else { return }
            let pick = LanguagePick.pick(en: Hypothesis(text: en, confidence: 0.5), th: Hypothesis(text: th, confidence: 0.5))
            partial = pick == .th ? th : en
        case .utterance(let en, let th): heard(en: en, th: th)
        case .interruptionBegan:
            interrupted = true
            stopSpeaking()
        case .interrupted:
            interrupted = false
            if phase == .listening { restart() }
        }
    }

    private func heard(en: Hypothesis?, th: Hypothesis?) {
        partial = ""
        lastActivity = Date()
        // Nach „Translator“ allein darf der nächste Satz ein nackter Befehl sein – auch wenn der Thai-Erkenner
        // für „pause“ etwas Plausibles liefert.
        let awake = Date() < awakeUntil
        if awake, let text = en?.text, let cmd = Commands.detect(text, awake: true) {
            Haptics.command()
            run(cmd)
            return
        }
        guard let lang = LanguagePick.pick(en: en, th: th) else { return }
        if lang == .en, let text = en?.text, let cmd = Commands.detect(text, awake: awake) {
            Haptics.command()
            run(cmd)
            return
        }
        guard !paused else { return }
        let text = (lang == .en ? en : th)?.text ?? ""
        let alt = (lang == .en ? th : en)?.text
        Haptics.heard()
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
        case .help: sheet = .help
        }
    }

    func flash(_ s: String, seconds: Double = 2.5) {
        notice = s
        noticeTask?.cancel()
        noticeTask = Task { try? await Task.sleep(for: .seconds(seconds)); if !Task.isCancelled { notice = nil } }
    }

    // MARK: Übersetzen

    /// Getippter Satz, Foto-Text oder Kurzbefehl.
    func submit(_ raw: String, speak: Bool = true) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        add(Entry(src: LanguagePick.ofTyped(text), text: text), speak: speak)
    }

    /// Satz aus dem Satzbuch: Übersetzung steht fest, kein Netz nötig.
    func say(_ p: Phrase) {
        let e = Entry(src: .en, text: p.en, translation: politeness.fill(p.th), provider: "phrasebook",
                      roman: p.roman.isEmpty ? nil : politeness.fillRoman(p.roman))
        entries.append(e)
        trim()
        persist()
        speak(e)
    }

    private func add(_ e: Entry, speak: Bool = true) {
        entries.append(e)
        trim()
        translate(e.id, speak: speak)
    }

    private func trim() {
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
    }

    private func translate(_ id: UUID, speak: Bool = true) {
        guard let e = entries.first(where: { $0.id == id }) else { return }
        let rev = (revisions[id] ?? 0) + 1
        revisions[id] = rev
        let job = Task { () -> String? in
            do {
                let r = try await translator.translate(e.text, from: e.src, allowOnline: allowOnline)
                let out = e.src == .en ? politeness.adjust(r.text) : r.text
                guard revisions[id] == rev else { return nil }   // inzwischen geändert
                update(id) { $0.translation = out; $0.provider = r.provider; $0.error = nil }
                persist()
                return out
            } catch {
                guard revisions[id] == rev else { return nil }
                update(id) { $0.error = error.localizedDescription }
                Haptics.warning()
                persist()
                return nil
            }
        }
        // Gleich in die Vorlese-Reihe stellen: so bleibt die Reihenfolge des Gesprächs erhalten,
        // auch wenn ein späterer Satz schneller übersetzt ist.
        if speak, autoSpeak, !paused {
            enqueueSpeech(id: id, lang: e.src.other, slow: false) { [weak self] in
                let text = await job.value
                guard let self, !self.paused, self.revisions[id] == rev else { return nil }
                return text
            }
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

    /// Erkannten Text von Hand korrigieren und neu übersetzen.
    func edit(_ id: UUID, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        stopSpeaking()
        update(id) { $0.text = t; $0.src = LanguagePick.ofTyped(t); $0.translation = nil; $0.error = nil; $0.alt = nil; $0.roman = nil }
        translate(id)
    }

    func retry(_ id: UUID) {
        update(id) { $0.error = nil }
        translate(id)
    }

    func delete(_ id: UUID) {
        if speakingID == id { stopSpeaking() }
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        stopSpeaking()
        entries.removeAll()
        persist()
    }

    // MARK: Favoriten

    private func phrase(for e: Entry) -> Phrase? {
        guard let t = e.translation else { return nil }
        let en = e.src == .en ? e.text : t
        let th = e.src == .en ? t : e.text
        return Phrase(en: en, th: th, roman: e.roman ?? "", category: "favorites")
    }

    func isFavorite(_ p: Phrase) -> Bool { favorites.contains { $0.en == p.en } }
    func isFavorite(_ e: Entry) -> Bool { phrase(for: e).map(isFavorite) ?? false }

    func toggleFavorite(_ p: Phrase) {
        if isFavorite(p) { favorites.removeAll { $0.en == p.en } } else { favorites.insert(p, at: 0) }
        Self.store(favorites, "favorites.json")
        Haptics.tap()
    }

    func toggleFavorite(_ e: Entry) {
        guard let p = phrase(for: e) else { return }
        toggleFavorite(p)
    }

    // MARK: Vorlesen (nacheinander; währenddessen hört das Mikrofon weg)

    /// `slow`: langsamer als eingestellt, z. B. wenn das Gegenüber nicht mitkam.
    func speak(_ e: Entry, slow: Bool = false) {
        guard let text = e.translation, !text.isEmpty else { return }
        enqueueSpeech(id: e.id, lang: e.src.other, slow: slow) { text }
    }

    /// Stellt eine Ausgabe in die Reihe. `text` darf warten (z. B. bis die Übersetzung da ist); nil = überspringen.
    private func enqueueSpeech(id: UUID, lang: Lang, slow: Bool, text produce: @escaping @MainActor () async -> String?) {
        let prev = speakChain
        pendingSpeech += 1
        let gen = speechGeneration
        speakChain = Task {
            await prev?.value
            let text = gen == speechGeneration ? await produce() : nil
            let r = slow ? max(0.4, rate * 0.65) : rate
            guard gen == speechGeneration, let text, !text.isEmpty else {   // gestoppt oder nichts zu sagen
                pendingSpeech -= 1
                if pendingSpeech == 0 { engine?.setMuted(false) }
                return
            }
            engine?.setMuted(true)
            let session = AVAudioSession.sharedInstance()
            if engine == nil {
                try? session.setCategory(.playback, options: [.duckOthers])
                try? session.setActive(true)
            } else if lang == .th && thaiOnSpeaker {
                // Mit Kopfhörern hört sonst nur man selbst die Thai-Ansage.
                try? session.overrideOutputAudioPort(.speaker)
            }
            speakingID = id
            await speaker.speak(text, lang: lang, rate: r, volume: volume)
            if speakingID == id { speakingID = nil }
            pendingSpeech -= 1
            if pendingSpeech == 0 {
                lastActivity = Date()
                try? await Task.sleep(for: .milliseconds(400))   // Nachhall nicht als Sprache werten
                if pendingSpeech == 0 {
                    if let engine {
                        try? session.overrideOutputAudioPort(.none)
                        engine.setMuted(false)
                    } else {
                        // Nur vorgelesen, nicht zugehört: Musik/Navi wieder laut machen.
                        try? session.setActive(false, options: .notifyOthersOnDeactivation)
                    }
                }
            }
        }
    }

    /// Bricht den laufenden Satz ab und verwirft alle, die noch warten.
    func stopSpeaking() {
        speechGeneration += 1
        speaker.stop()
    }

    // MARK: Speicher

    private static func url(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func store<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) {
            // „UnlessOpen“: auch bei gesperrtem Gerät (Hintergrund-Zuhören) speicherbar.
            try? data.write(to: url(name), options: [.atomic, .completeFileProtectionUnlessOpen])
        }
    }

    private func persist() {
        if historyDays == 0 {
            try? FileManager.default.removeItem(at: Self.url("history.json"))
        } else {
            Self.store(entries, "history.json")
        }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f
    }()

    var transcript: String {
        entries.map {
            "[\(Self.stamp.string(from: $0.date))] \($0.src == .en ? "EN" : "TH"): \($0.text)\n→ \($0.translation ?? "–")"
        }.joined(separator: "\n\n")
    }
}
