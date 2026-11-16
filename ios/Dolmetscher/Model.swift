// Model.swift – Zustand der App: Zuhören, Sprachwahl, Befehle, Übersetzen, Vorlesen, Verlauf, Satzbuch.
import AVFoundation
import Observation
import SwiftUI
import os

private let debugLog = Logger(subsystem: "dolmetscher", category: "model")

struct Entry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var src: Lang
    /// Zielsprache. Fehlt in alten Verläufen (nur en/th): dann die jeweils andere der beiden.
    var dst: Lang?
    var text: String
    var translation: String?
    var error: String?
    /// Was der Erkenner der anderen Sprache gehört hat – für „andere Sprache war gemeint“.
    var alt: String?
    /// "apple" (offline), "google"/"mymemory" (online), "phrasebook"
    var provider: String?
    /// Aussprache-Hilfe (nur Satzbuch)
    var roman: String?

    var target: Lang { dst ?? (src == .th ? .en : .th) }
}

enum AppSheet: String, Identifiable {
    case settings, phrasebook, photo, help, emergency, baht
    var id: String { rawValue }
}

@MainActor @Observable
final class InterpreterModel {
    static let shared = InterpreterModel()

    enum Phase: Equatable { case idle, loading, listening, failed(String) }

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

    /// Kurz nach „Verlauf leeren“: zurückholbar.
    var canUndoClear = false
    /// Sprachmodell müsste über Mobilfunk geladen werden: erst fragen.
    var cellularDownloadPrompt = false
    /// Mikrofon oder Spracherkennung verweigert: Knopf „Einstellungen öffnen“ zeigen.
    var micDenied = false
    /// „Jetzt Sie“ / „Jetzt ich“: diese Sprache wird als Nächstes erwartet (bis zum nächsten Satz oder Ablauf).
    var expected: Lang?

    var pair: LangPair {
        didSet {
            guard pair != oldValue else { return }
            save("langMine", pair.mine.rawValue); save("langPartner", pair.partner.rawValue)
            if mode.effective(pair) != mode { mode = mode.effective(pair) }
            if phase == .listening { restart() }
            Task { await refreshOffline() }
        }
    }
    var features: PairFeatures { pair.features }
    var mode: Direction { didSet { save("mode", mode.rawValue); if phase == .listening && oldValue != mode { restart() } } }
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
    var emergency: EmergencyInfo { didSet { files.store(emergency, "emergency.json") } }

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
    @ObservationIgnored private let files: JSONStore
    /// Verlauf/Favoriten waren beim Start nicht lesbar (gesperrtes Gerät): nie mit leerer Liste überschreiben.
    @ObservationIgnored private var historyBlocked = false
    @ObservationIgnored private var favoritesBlocked = false
    @ObservationIgnored private var undo = UndoBuffer<[Entry]>()
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var lastRecognizerFailure = Date.distantPast
    /// Einmal erlaubt: Sprachmodell trotz Mobilfunk laden.
    @ObservationIgnored private var cellularAllowed = false
    @ObservationIgnored private var expectedUntil = Date.distantPast
    @ObservationIgnored private var expectTask: Task<Void, Never>?

    /// Standard „aus“: ohne ausdrückliche Erlaubnis gehen keine Gespräche an Google/MyMemory.
    nonisolated static func allowOnlineSetting(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: "allowOnline") as? Bool ?? false }
    nonisolated static func pairSetting(_ d: UserDefaults = .standard) -> LangPair {
        LangPair.load(mine: d.string(forKey: "langMine"), partner: d.string(forKey: "langPartner"))
    }

    init(files: JSONStore = .standard) {
        let d = UserDefaults.standard
        self.files = files
        let pair = Self.pairSetting(d)
        self.pair = pair
        mode = Direction.migrate(d.string(forKey: "mode"), pair: pair).effective(pair)
        pauseSeconds = d.object(forKey: "pauseSeconds") as? Double ?? 0.8
        rate = d.object(forKey: "rate") as? Double ?? 1.0
        volume = d.object(forKey: "volume") as? Double ?? 1.0
        allowOnline = Self.allowOnlineSetting(d)
        autoSpeak = d.object(forKey: "autoSpeak") as? Bool ?? true
        uiLang = d.string(forKey: "uiLang") ?? L10n.systemLang()
        politeness = Politeness(rawValue: d.string(forKey: "politeness") ?? "") ?? .male
        haptics = d.object(forKey: "haptics") as? Bool ?? true
        autoStopMinutes = d.object(forKey: "autoStopMinutes") as? Int ?? 10
        background = d.object(forKey: "background") as? Bool ?? false
        headset = d.object(forKey: "headset") as? Bool ?? false
        historyDays = d.object(forKey: "historyDays") as? Int ?? 30
        thaiOnSpeaker = d.object(forKey: "thaiOnSpeaker") as? Bool ?? true
        emergency = files.load(EmergencyInfo.self, "emergency.json").value ?? EmergencyInfo()
        L10n.lang = uiLang
        Haptics.enabled = haptics
        loadHistory()
        loadFavorites()
        pruneHistory()
        Task { await refreshOffline() }
        // Gerät war beim Start gesperrt: nach dem Entsperren nachladen.
        NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in InterpreterModel.shared.reloadIfBlocked() }
        }
        #if DEBUG
        // Test im Simulator: mit DOLMETSCHER_AUDIO_FILES gleich loslegen.
        if ProcessInfo.processInfo.environment["DOLMETSCHER_AUTOSTART"] != nil { Task { @MainActor in self.start() } }
        // Verfügbarkeit aller Sprachen ins Log (Kategorie „langs“) – was kann dieses Gerät wirklich?
        if ProcessInfo.processInfo.environment["DOLMETSCHER_LOG_LANGS"] != nil {
            Task.detached { _ = await LangCheck.levels(with: .en); _ = await LangCheck.level(.en, with: .th) }
        }
        #endif
    }

    private func loadHistory() {
        switch files.load([Entry].self, "history.json") {
        case .ok(let e): entries = e + entries; historyBlocked = false
        case .missing: historyBlocked = false
        case .corrupt: files.quarantine("history.json"); historyBlocked = false
        case .unreadable: historyBlocked = true
        }
    }

    private func loadFavorites() {
        switch files.load([Phrase].self, "favorites.json") {
        case .ok(let f): favorites = f + favorites.filter { n in !f.contains { $0.en == n.en } }; favoritesBlocked = false
        case .missing: favoritesBlocked = false
        case .corrupt: files.quarantine("favorites.json"); favoritesBlocked = false
        case .unreadable: favoritesBlocked = true
        }
    }

    /// Dateien waren nicht lesbar (gesperrt gestartet): jetzt laden, Neues dahinter behalten und speichern.
    func reloadIfBlocked() {
        if historyBlocked {
            loadHistory()
            if !historyBlocked { persist() }
        }
        if favoritesBlocked {
            loadFavorites()
            if !favoritesBlocked { files.store(favorites, "favorites.json") }
        }
    }

    /// Für Tests: blockiert das Speichern gerade?
    var isHistoryBlocked: Bool { historyBlocked }

    private func save(_ key: String, _ value: Any) { d.set(value, forKey: key) }

    var isBusy: Bool { phase == .loading }
    var isListening: Bool { phase == .listening }

    func refreshOffline() async {
        let p = pair
        let a = await Translator.offlineInstalled(from: p.mine, to: p.partner)
        let b = await Translator.offlineInstalled(from: p.partner, to: p.mine)
        offlineReady = a && b
    }

    // MARK: Zuhören

    func toggle() { phase == .listening || phase == .loading ? stop() : start() }

    func start() {
        guard !isBusy, !isListening else { return }
        phase = .loading
        paused = false
        micDenied = false
        generation += 1
        let mine = generation
        let pendingStop = stopTask
        let options = AudioOptions(headset: headset)
        let langs = mode.langs(pair), pause = pauseSeconds
        let cellularOK = cellularAllowed
        cellularAllowed = false
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
                    // Fehlt ein Sprachmodell, lädt das System es jetzt (einmalig, groß): nicht ungefragt über
                    // Mobilfunk/Roaming und ohne Netz mit klarer Meldung statt Hängen.
                    if AudioCapture.debugFiles == nil, await LangRecognizer.needsDownload(langs) {
                        let net = NetStatus.shared
                        if !net.online { throw SpeechError.downloadOffline }
                        if net.expensive && !cellularOK {
                            if generation == mine { phase = .idle; cellularDownloadPrompt = true }
                            return
                        }
                    }
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
                    if case .denied? = error as? SpeechError { micDenied = true }
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

    /// Nach Rückfrage: Sprachmodell trotz Mobilfunk laden.
    func startAllowingCellular() {
        cellularAllowed = true
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
        case .partial(let seen):
            guard !paused else { return }
            // Gleiche Wahl wie für den fertigen Satz (Schrift, echte Konfidenz) – nicht immer Englisch.
            partial = LanguagePick.pick(seen, pair: pair, bias: turnBias, expect: activeExpectation).flatMap { seen[$0]?.text } ?? ""
        case .utterance(let heard): self.heard(heard)
        case .failed(let why):
            guard phase == .listening else { return }
            // Ein Erkenner ist ausgefallen: einmal neu starten; fällt er gleich wieder aus, Fehler zeigen.
            let again = Date().timeIntervalSince(lastRecognizerFailure) < 60
            lastRecognizerFailure = Date()
            if again {
                stop()
                phase = .failed(T("err_recognizer") + " (\(why))")
                Haptics.error()
            } else {
                restart()
                flash("⚠️ " + T("recognizer_restarted"), seconds: 4)
            }
        case .interruptionBegan:
            interrupted = true
            stopSpeaking()
        case .interrupted:
            interrupted = false
            if phase == .listening { restart() }
        }
    }

    private func heard(_ hyps: [Lang: Hypothesis]) {
        partial = ""
        lastActivity = Date()
        let pair = pair
        let commands = features.voiceCommands
        // Nach „Translator“ allein darf der nächste Satz ein nackter Befehl sein – auch wenn der Erkenner
        // der anderen Sprache für „pause“ etwas Plausibles liefert.
        let awake = Date() < awakeUntil
        if commands, awake, let text = hyps[.en]?.text, let cmd = Commands.detect(text, awake: true) {
            Haptics.command()
            run(cmd)
            return
        }
        guard let lang = LanguagePick.pick(hyps, pair: pair, bias: turnBias, expect: activeExpectation),
              pair.contains(lang) else { return }
        if commands, lang == .en, let text = hyps[.en]?.text, let cmd = Commands.detect(text, awake: awake) {
            Haptics.command()
            run(cmd)
            return
        }
        guard !paused else { return }
        let text = hyps[lang]?.text ?? ""
        let alt = hyps[pair.other(lang)]?.text
        clearExpectation()
        Haptics.heard()
        add(Entry(src: lang, dst: pair.other(lang), text: text, alt: alt))
        #if DEBUG
        debugLog.info("heard \(lang.rawValue, privacy: .public): \(text, privacy: .public)")
        #endif
    }

    /// Gesprächs-Hinweis für die Sprachwahl: die andere Sprache des letzten gesprochenen Satzes.
    private var turnBias: Lang? {
        LanguagePick.turnBias(lastSpoken: entries.last(where: { $0.provider != "phrasebook" })?.src, pair: pair)
    }

    private var activeExpectation: Lang? { Date() < expectedUntil ? expected : nil }

    /// „Jetzt Sie“: der nächste Satz kommt in `lang`. Läuft nur ein Erkenner der anderen Sprache, wird umgeschaltet
    /// (kostet einen Neustart); im Automatik-Modus genügt der Hinweis an die Sprachwahl.
    func expectSpeaker(_ lang: Lang) {
        guard pair.contains(lang) else { return }
        expected = lang
        expectedUntil = Date().addingTimeInterval(20)
        if !mode.langs(pair).contains(lang) { mode = lang == pair.mine ? .mine : .partner }
        if !isListening && !isBusy { start() }
        Haptics.tap()
        expectTask?.cancel()
        expectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.expected = nil
        }
    }

    private func clearExpectation() {
        expectTask?.cancel()
        expected = nil
        expectedUntil = .distantPast
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
        let src = typedLang(text)
        add(Entry(src: src, dst: pair.other(src), text: text), speak: speak)
    }

    /// Sprache eines getippten Textes; bei gleicher Schrift gilt die eingestellte Richtung.
    private func typedLang(_ text: String) -> Lang {
        LanguagePick.ofTyped(text, pair: pair, fallback: mode.effective(pair) == .partner ? pair.partner : pair.mine)
    }

    /// Satz aus dem Satzbuch: Übersetzung steht fest, kein Netz nötig.
    func say(_ p: Phrase) {
        let src = p.srcLang, dst = p.dstLang
        let fixed = dst == .th ? politeness.fill(p.th) : p.th
        let roman = p.roman.isEmpty ? nil : (dst == .th ? politeness.fillRoman(p.roman) : p.roman)
        let e = Entry(src: src, dst: dst, text: p.en, translation: fixed, provider: "phrasebook", roman: roman)
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
                let r = try await translator.translate(e.text, from: e.src, to: e.target, allowOnline: allowOnline)
                let out = e.target == .th ? politeness.adjust(r.text) : r.text
                guard revisions[id] == rev else { return nil }   // inzwischen geändert
                update(id) { $0.translation = out; $0.provider = r.provider; $0.error = nil }
                persist()
                // VoiceOver: Übersetzung ansagen, wenn sie nicht ohnehin vorgelesen wird.
                if UIAccessibility.isVoiceOverRunning && !(speak && autoSpeak && !paused) {
                    AccessibilityNotification.Announcement(T("a11y_ready") + ": " + out).post()
                }
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
            enqueueSpeech(id: id, lang: e.target, slow: false) { [weak self] in
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
        update(id) { $0.alt = e.text; $0.text = alt; $0.src = e.target; $0.dst = e.src; $0.translation = nil; $0.error = nil }
        translate(id)
    }

    /// Erkannten Text von Hand korrigieren und neu übersetzen.
    func edit(_ id: UUID, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        stopSpeaking()
        // Sprache neu bestimmen – bei gleicher Schrift bleibt die bisherige Richtung des Eintrags.
        let old = entries.first { $0.id == id }
        let src = pair.distinguishable ? typedLang(t) : (old?.src ?? typedLang(t))
        let dst = pair.contains(src) ? pair.other(src) : (old?.target ?? pair.other(src))
        update(id) { $0.text = t; $0.src = src; $0.dst = dst; $0.translation = nil; $0.error = nil; $0.alt = nil; $0.roman = nil }
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

    /// Ganzen Verlauf leeren – für einige Sekunden zurückholbar (Sprachbefehl „clear“ kann ein Verhörer sein).
    func clear() {
        guard !entries.isEmpty else { return }
        stopSpeaking()
        undo.keep(entries, seconds: 8)
        entries.removeAll()
        persist()
        canUndoClear = true
        flash("🗑 " + T("cleared"), seconds: 8)
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self else { return }
            self.canUndoClear = false
            self.undo.drop()
        }
    }

    func undoClear() {
        undoTask?.cancel()
        canUndoClear = false
        guard let old = undo.take() else { return }
        entries = old + entries
        trim()
        persist()
        flash("↩️ " + T("restored"))
    }

    // MARK: Favoriten

    private func phrase(for e: Entry) -> Phrase? {
        guard let t = e.translation else { return nil }
        if e.src == .en && e.target == .th {
            return Phrase(en: e.text, th: t, roman: e.roman ?? "", category: "favorites")
        }
        if e.src == .th && e.target == .en {
            return Phrase(en: t, th: e.text, roman: e.roman ?? "", category: "favorites")
        }
        return Phrase(en: e.text, th: t, roman: e.roman ?? "", category: "favorites", src: e.src, dst: e.target)
    }

    func isFavorite(_ p: Phrase) -> Bool { favorites.contains { $0.en == p.en } }
    func isFavorite(_ e: Entry) -> Bool { phrase(for: e).map(isFavorite) ?? false }

    func toggleFavorite(_ p: Phrase) {
        if isFavorite(p) { favorites.removeAll { $0.en == p.en } } else { favorites.insert(p, at: 0) }
        if !favoritesBlocked { files.store(favorites, "favorites.json") }
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
        enqueueSpeech(id: e.id, lang: e.target, slow: slow) { text }
    }

    /// Fester Satz laut ausgeben (Notruf-Kurzbefehl), unabhängig vom Verlauf.
    func announce(_ text: String, lang: Lang) {
        enqueueSpeech(id: UUID(), lang: lang, slow: false, loud: true) { text }
    }

    /// Stellt eine Ausgabe in die Reihe. `text` darf warten (z. B. bis die Übersetzung da ist); nil = überspringen.
    private func enqueueSpeech(id: UUID, lang: Lang, slow: Bool, loud: Bool = false,
                               text produce: @escaping @MainActor () async -> String?) {
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
            } else if lang == pair.partner && thaiOnSpeaker {
                // Mit Kopfhörern hört sonst nur man selbst die Ansage für das Gegenüber.
                try? session.overrideOutputAudioPort(.speaker)
            }
            speakingID = id
            await speaker.speak(text, lang: lang, rate: r, volume: loud ? 1 : volume)
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

    func persist() {
        if historyDays == 0 {
            files.remove("history.json")
        } else if !historyBlocked {
            // War die Datei beim Start nicht lesbar, nie mit der (unvollständigen) Liste überschreiben.
            files.store(entries, "history.json")
        }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f
    }()

    var transcript: String {
        entries.map {
            "[\(Self.stamp.string(from: $0.date))] \($0.src.rawValue.uppercased())→\($0.target.rawValue.uppercased()): \($0.text)\n→ \($0.translation ?? "–")"
        }.joined(separator: "\n\n")
    }
}
