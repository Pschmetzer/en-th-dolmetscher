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
    /// Rückübersetzung der Übersetzung in die Ausgangssprache (nur auf dem Gerät) – zur Kontrolle.
    var back: String?

    /// Umschrift: die geprüfte aus dem Satzbuch, sonst automatisch (th/ja/ko/zh).
    var romanized: String? { roman ?? translation.flatMap { Romanizer.latin($0, target) } }
    /// Rückübersetzung weicht deutlich ab – Übersetzung prüfen.
    var backDeviates: Bool { back.map { BackCheck.deviates(original: text, back: $0) } ?? false }

    var target: Lang { dst ?? (src == .th ? .en : .th) }
}

enum AppSheet: String, Identifiable {
    case settings, phrasebook, photo, help, emergency, baht, allergy, privacy, prep, places, helpNow
    #if DEBUG
    case widgetPreview
    #endif
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
    /// Satz ist zu Ende gesprochen, Ergebnis kommt gleich: Vorschau stehen lassen („Übersetze …“).
    var finishing = false
    /// Auto-Stopp steht kurz bevor (30 s): Hinweis mit „Weiter“.
    var idleWarning = false
    /// iPhone ist heiß: nur eine Sprache, keine Live-Vorschau.
    var hot = false
    /// Push-to-talk: Knopf wird gerade gehalten.
    var pttHeld = false
    /// Kurzbefehl „Letzte Übersetzung groß“: diese Blase groß zeigen.
    var bigRequest: UUID?
    /// Gespeicherte Ziele (Taxi, Tuk-Tuk).
    var places: [Place] = [] { didSet { files.store(places, "places.json") } }

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
    /// Halten zum Sprechen statt Dauer-Zuhören (spart Akku, sicherer in Menschenmengen).
    var pushToTalk: Bool { didSet { save("pushToTalk", pushToTalk); applyMute() } }
    /// Live-Aktivität (Sperrbildschirm, Dynamic Island) beim Zuhören.
    var liveActivity: Bool { didSet { save("liveActivity", liveActivity); liveUpdate() } }
    /// Rückübersetzung (offline) unter jeder Übersetzung anzeigen.
    var backCheck: Bool { didSet { save("backCheck", backCheck); if !backCheck { clearBack() } } }
    /// Umschrift unter Thai/Japanisch/Koreanisch/Chinesisch.
    var showRoman: Bool { didSet { save("showRoman", showRoman) } }
    /// Älteren Verlauf erst nach Face ID / Code zeigen.
    var lockHistory: Bool { didSet { save("lockHistory", lockHistory); if !lockHistory { historyUnlocked = true } } }
    /// Gesperrt: Einträge vor diesem Zeitpunkt sind verborgen, bis entsperrt wird.
    var historyUnlocked = true
    @ObservationIgnored private var lockedBefore = Date()
    /// Jetzt wäre ein guter Moment für die Bewertungsbitte (die Ansicht fragt, wenn nichts offen ist).
    var reviewDue = false
    @ObservationIgnored private var review = ReviewGate.load(.standard)
    @ObservationIgnored private var sessionTranslations = 0

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
    @ObservationIgnored private var finishingTask: Task<Void, Never>?
    /// Für Tests: andere Spracherkennung einsetzen (Standard: Apple).
    @ObservationIgnored var makeEngine: @MainActor () -> any SpeechEngine = { AppleSpeechEngine() }
    /// Für Tests: Sprachmodell-Prüfung und Whisper überspringen.
    @ObservationIgnored var checkModels = true
    @ObservationIgnored private var lastMute: Bool?
    @ObservationIgnored private var pttDraining = false
    @ObservationIgnored private var drainTask: Task<Void, Never>?
    @ObservationIgnored private var autoSeq = 0
    /// Bei Hitze von „Automatisch“ umgeschaltet: beim Abkühlen zurück.
    @ObservationIgnored private var coolSwitched = false

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
        backCheck = d.object(forKey: "backCheck") as? Bool ?? true
        showRoman = d.object(forKey: "showRoman") as? Bool ?? true
        lockHistory = d.object(forKey: "lockHistory") as? Bool ?? false
        pushToTalk = d.object(forKey: "pushToTalk") as? Bool ?? false
        liveActivity = d.object(forKey: "liveActivity") as? Bool ?? true
        historyUnlocked = !lockHistory
        L10n.lang = uiLang
        Haptics.enabled = haptics
        loadHistory()
        loadFavorites()
        places = files.load([Place].self, "places.json").value ?? []
        pruneHistory()
        Task { await refreshOffline() }
        // Gerät war beim Start gesperrt: nach dem Entsperren nachladen.
        NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in InterpreterModel.shared.reloadIfBlocked() }
        }
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in InterpreterModel.shared.thermalChanged() }
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
        sessionTranslations = 0
        generation += 1
        let mine = generation
        let pendingStop = stopTask
        let options = AudioOptions(headset: headset)
        let langs = mode.langs(pair), pause = pauseSeconds
        let cellularOK = cellularAllowed
        cellularAllowed = false
        // Whisper nur auf Wunsch und nur mit vollständigem Modell – sonst Apple mit Hinweis.
        let wantWhisper = checkModels && WhisperStore.shared.enabled
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
                    if checkModels, AudioCapture.debugFiles == nil, await LangRecognizer.needsDownload(langs) {
                        let net = NetStatus.shared
                        if !net.online { throw SpeechError.downloadOffline }
                        if net.expensive && !cellularOK {
                            if generation == mine { phase = .idle; cellularDownloadPrompt = true }
                            return
                        }
                    }
                    let a = makeEngine()
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
                // Läuft gerade eine Ausgabe (z. B. getippter Satz), soll die neue Aufnahme sie nicht hören;
                // bei Push-to-talk hört sie erst beim Halten zu.
                lastMute = nil
                phase = .listening
                applyMute()
                lastActivity = Date()
                Haptics.success()
                UIApplication.shared.isIdleTimerDisabled = true
                listenTask = Task { [weak self] in
                    for await ev in e.events { self?.handle(ev) }
                }
                watchIdle()
                liveUpdate()
                if hot { flash("🌡 " + T("hot_single"), seconds: 5) }
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

    /// `endConversation`: false bei einem Neustart (Moduswechsel, Kopfhörer) – dasselbe Gespräch läuft weiter.
    func stop(endConversation: Bool = true) {
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
        lastMute = nil
        listenTask?.cancel()
        stopSpeaking()
        if endConversation { conversationEnded() }
        phase = .idle
        partial = ""; level = 0; hearing = false; finishing = false; idleWarning = false; pttHeld = false
        if endConversation { LiveActivityController.shared.end() }
        UIApplication.shared.isIdleTimerDisabled = false
        Haptics.tap()
        stopTask = Task { await e.stop() }
    }

    private func restart() {
        let n = sessionTranslations
        stop(endConversation: false)
        start()
        sessionTranslations = n   // Neustart (Moduswechsel, Kopfhörer) ist dasselbe Gespräch
    }

    /// Ende eines Gesprächs: zählt für die Bewertungsbitte.
    private func conversationEnded() {
        review.conversationEnded(translations: sessionTranslations)
        sessionTranslations = 0
        review.save(d)
        if review.shouldAsk(version: Self.version, busy: false) { reviewDue = true }
    }

    nonisolated static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Die Ansicht hat gefragt (oder fragt jetzt) – höchstens einmal je Version.
    func reviewAsked() {
        reviewDue = false
        review.asked(version: Self.version)
        review.save(d)
    }

    /// Nie mitten im Gespräch fragen.
    var canAskReview: Bool { reviewDue && phase == .idle && speakingID == nil && sheet == nil }

    /// Nach Rückfrage: Sprachmodell trotz Mobilfunk laden.
    func startAllowingCellular() {
        cellularAllowed = true
        start()
    }

    /// App geht in den Hintergrund: ohne Hintergrund-Einstellung aufhören zuzuhören.
    func enteredBackground() {
        lockNow()
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
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isListening else { continue }
                let limit = IdlePolicy.limit(minutes: self.autoStopMinutes, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
                switch IdlePolicy.state(idle: Date().timeIntervalSince(self.lastActivity), limit: limit) {
                case .ok: self.idleWarning = false
                case .warn:
                    if !self.idleWarning { self.idleWarning = true; Haptics.warning() }
                case .stop:
                    self.stop()
                    self.flash("💤 " + T("auto_stopped"))
                    return
                }
            }
        }
    }

    /// Jede Bedienung zählt als Aktivität – der Auto-Stopp soll nicht mitten in der Benutzung zuschlagen.
    func touch() {
        lastActivity = Date()
        idleWarning = false
    }

    private func handle(_ ev: SpeechEvent) {
        switch ev {
        case .level(let l): level = l
        case .hearing(let h):
            hearing = h
            if h {
                touch(); finishing = false
            } else if !partial.isEmpty {
                // Satz zu Ende: Vorschau mit „Übersetze …“ stehen lassen, bis das Ergebnis da ist.
                finishing = true
                finishingTask?.cancel()
                finishingTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled, let self, self.finishing else { return }
                    self.finishing = false; self.partial = ""
                }
            }
            liveUpdate()
        case .partial(let seen):
            guard !paused, !hot else { return }   // heiß: keine Live-Vorschau (spart Rechenzeit)
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
        finishing = false
        touch()
        if pttDraining { pttDraining = false; drainTask?.cancel(); applyMute() }
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
        case .pause: paused = true; stopSpeaking(); flash("⏸ " + T("paused")); liveUpdate()
        case .resume: paused = false; flash("▶️ " + T("resumed")); liveUpdate()
        case .repeat: if let last = visibleEntries.last(where: { $0.translation != nil }) { speak(last) }
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
        touch()
        let src = typedLang(text)
        add(Entry(src: src, dst: pair.other(src), text: text), speak: speak)
    }

    /// Sprache eines getippten Textes; bei gleicher Schrift gilt die eingestellte Richtung.
    private func typedLang(_ text: String) -> Lang {
        LanguagePick.ofTyped(text, pair: pair, fallback: mode.effective(pair) == .partner ? pair.partner : pair.mine)
    }

    /// Satz aus dem Satzbuch: Übersetzung steht fest, kein Netz nötig.
    func say(_ p: Phrase) {
        touch()
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
        // „Satzbuch zuerst“: passt der Satz auf einen geprüften Satz, dessen Thai-Fassung nehmen (offline, sofort).
        if e.target == .th, features.thaiExtras, let p = Phrasebook.match(e.text, lang: e.src) {
            var fixed = e
            fixed.translation = politeness.fill(p.th)
            fixed.roman = p.roman.isEmpty ? nil : politeness.fillRoman(p.roman)
            fixed.provider = "phrasebook"
            entries.append(fixed)
            trim()
            persist()
            if speak { sessionTranslations += 1 }
            liveUpdate()
            if speak, autoSpeak, !paused { self.speak(fixed) }
            return
        }
        entries.append(e)
        trim()
        translate(e.id, speak: speak)
    }

    private func trim() {
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
    }

    /// `force`: auch vorlesen, wenn „Automatisch vorlesen“ aus ist (Kurzbefehl „Sage …“).
    private func translate(_ id: UUID, speak: Bool = true, force: Bool = false) {
        guard let e = entries.first(where: { $0.id == id }) else { return }
        let rev = (revisions[id] ?? 0) + 1
        revisions[id] = rev
        let job = Task { () -> String? in
            do {
                let r = try await translator.translate(e.text, from: e.src, to: e.target, allowOnline: allowOnline)
                let out = e.target == .th ? politeness.adjust(r.text) : r.text
                guard revisions[id] == rev else { return nil }   // inzwischen geändert
                update(id) { $0.translation = out; $0.provider = r.provider; $0.error = nil; $0.back = nil }
                persist()
                if speak { sessionTranslations += 1 }
                liveUpdate()
                if backCheck { backTranslate(id, rev: rev, text: out, from: e.target, to: e.src) }
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
        if speak, autoSpeak || force, !paused {
            autoSeq += 1
            let seq = autoSeq
            enqueueSpeech(id: id, lang: e.target, slow: false) { [weak self] in
                let text = await job.value
                guard let self, !self.paused, self.revisions[id] == rev else { return nil }
                // Stau: liegen schon zwei neuere Sätze an, diesen nicht mehr vorlesen (steht ja im Verlauf).
                if !force, SpeechBacklog.skip(seq: seq, latest: self.autoSeq) { self.flash("⏭ " + T("speech_skipped")); return nil }
                return text
            }
        }
    }

    /// Übersetzung zurück in die Ausgangssprache – nur mit Offline-Paket (nichts geht dafür ins Netz),
    /// ohne Vorlesen. Fehlt das Paket, still überspringen.
    private func backTranslate(_ id: UUID, rev: Int, text: String, from: Lang, to: Lang) {
        Task {
            guard await Translator.offlineInstalled(from: from, to: to),
                  let r = try? await translator.translate(text, from: from, to: to, allowOnline: false),
                  revisions[id] == rev, backCheck else { return }
            update(id) { $0.back = r.text }
            persist()
        }
    }

    private func clearBack() {
        for i in entries.indices { entries[i].back = nil }
        persist()
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
        // Gesperrt: nur die sichtbaren Sätze – der verborgene Verlauf lässt sich nicht ohne Face ID löschen.
        let gone = visibleEntries
        guard !gone.isEmpty else { return }
        stopSpeaking()
        undo.keep(gone, seconds: 8)
        let ids = Set(gone.map(\.id))
        entries.removeAll { ids.contains($0.id) }
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
        entries = (old + entries).sorted { $0.date < $1.date }
        trim()
        persist()
        flash("↩️ " + T("restored"))
    }

    // MARK: Antwortkarten, Kurzbefehle

    /// Das Gegenüber tippt eine Antwortkarte (Ja/Nein/Weiß nicht): feste Sätze, kein Netz, sofort vorgelesen.
    func answer(_ key: PartnerKey) {
        let src = pair.partner, dst = pair.mine
        let e = Entry(src: src, dst: dst, text: PartnerPhrases.text(key, src), translation: PartnerPhrases.text(key, dst), provider: "card")
        addFixed(e)
    }

    /// Antwortkarte „Zahl“: Ziffern, für Thai zusätzlich als Zahlwort.
    func answerNumber(_ digits: String) {
        guard !digits.isEmpty else { return }
        let src = pair.partner, dst = pair.mine
        let e = Entry(src: src, dst: dst, text: NumberCard.spoken(digits, in: src), translation: NumberCard.spoken(digits, in: dst), provider: "card")
        addFixed(e)
    }

    private func addFixed(_ e: Entry) {
        touch()
        entries.append(e)
        trim()
        persist()
        sessionTranslations += 1
        clearExpectation()
        Haptics.heard()
        if autoSpeak { speak(e) }
    }

    /// Kurzbefehl „Sage in Partnersprache“: Text aus meiner Sprache übersetzen und laut vorlesen.
    func sayInPartner(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let e = Entry(src: pair.mine, dst: pair.partner, text: text)
        entries.append(e)
        trim()
        translate(e.id, speak: true, force: true)
    }

    // MARK: Verlauf sperren (Face ID)

    /// Sichtbare Einträge: gesperrt nur die seit dem Sperren neuen.
    var visibleEntries: [Entry] {
        guard lockHistory, !historyUnlocked else { return entries }
        return entries.filter { $0.date >= lockedBefore }
    }

    var hiddenCount: Int { entries.count - visibleEntries.count }

    func lockNow() {
        guard lockHistory else { return }
        historyUnlocked = false
        lockedBefore = Date()
    }

    func unlockHistory() {
        Task {
            if await DeviceAuth.authenticate(reason: T("lock_reason")) { historyUnlocked = true }
        }
    }

    // MARK: Notfallkarte übersetzen

    /// Einzelner Text ohne Verlaufseintrag (Allergie-Karte in nicht hinterlegter Sprache).
    func translateText(_ text: String, from: Lang, to: Lang) async -> String? {
        try? await translator.translate(text, from: from, to: to, allowOnline: allowOnline).text
    }

    /// Freitext der Notfallkarte (Allergien, Medizinisches) in die Partnersprache – als „maschinell“ gekennzeichnet.
    func translateEmergency() async {
        let to = pair.partner
        var out: [String: String] = [:]
        var failed = false
        for (key, value) in emergency.translatable where !value.isEmpty {
            // Die Karte schreibt man in der eigenen Sprache; steht schon die Partnersprache da, bleibt es so.
            let src = LanguagePick.ofTyped(value, pair: pair, fallback: pair.mine)
            if src == to { out[key] = value; continue }
            if let r = try? await translator.translate(value, from: src, to: to, allowOnline: allowOnline) {
                out[key] = to == .th ? politeness.ensureEnding(r.text) : r.text
            } else { failed = true }
        }
        emergency.translated = out
        emergency.translatedLang = to.rawValue
        emergency.translatedSource = emergency.translatableHash
        if failed { flash("⚠️ " + T(allowOnline ? "err_translate" : "err_offline_missing"), seconds: 5) }
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
                if pendingSpeech == 0 { applyMute() }
                return
            }
            applyMute()
            let session = AVAudioSession.sharedInstance()
            let toPartner = lang == pair.partner && thaiOnSpeaker
            if engine == nil {
                // Getippt oder Satzbuch: für das Gegenüber auch mit Kopfhörern über den Lautsprecher.
                if toPartner {
                    try? session.setCategory(.playAndRecord, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP])
                    try? session.setActive(true)
                    try? session.overrideOutputAudioPort(.speaker)
                } else {
                    try? session.setCategory(.playback, options: [.duckOthers])
                    try? session.setActive(true)
                }
            } else if toPartner {
                // Mit Kopfhörern hört sonst nur man selbst die Ansage für das Gegenüber.
                try? session.overrideOutputAudioPort(.speaker)
            }
            speakingID = id
            liveUpdate()
            await speaker.speak(text, lang: lang, rate: r, volume: loud ? 1 : volume)
            if speakingID == id { speakingID = nil; liveUpdate() }
            pendingSpeech -= 1
            if pendingSpeech == 0 {
                lastActivity = Date()
                try? await Task.sleep(for: .milliseconds(400))   // Nachhall nicht als Sprache werten
                if pendingSpeech == 0 {
                    if engine != nil {
                        try? session.overrideOutputAudioPort(.none)
                        applyMute()
                    } else {
                        try? session.overrideOutputAudioPort(.none)
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

    // MARK: Push-to-talk, Wärme, Live-Aktivität

    /// Eine Quelle für die Stummschaltung: während der Ausgabe immer, bei Push-to-talk außer beim Halten
    /// (und kurz danach, bis der Satz abgeschlossen ist).
    var shouldMute: Bool { pendingSpeech > 0 || (pushToTalk && !pttHeld && !pttDraining) }

    private func applyMute() {
        guard let engine else { return }
        let m = shouldMute
        guard m != lastMute else { return }
        lastMute = m
        engine.setMuted(m)
    }

    /// Knopf gedrückt: zuhören (startet bei Bedarf).
    func pttPress() {
        touch()
        pttHeld = true
        drainTask?.cancel()
        pttDraining = false
        if !isListening && !isBusy { start() }
        applyMute()
        Haptics.tap()
        liveUpdate()
    }

    /// Knopf losgelassen: Satz sofort abschließen, danach wieder taub.
    func pttRelease() {
        guard pttHeld else { return }
        pttHeld = false
        pttDraining = true
        engine?.flush()
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))   // so lange darf das Ergebnis brauchen
            guard !Task.isCancelled, let self else { return }
            self.pttDraining = false
            self.applyMute()
        }
        liveUpdate()
    }

    /// Wärme: ab „ernst“ nur noch eine Sprache (halbe Rechenlast), beim Abkühlen zurück auf Automatisch.
    func thermalChanged(_ state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) {
        let isHot = EnergyPolicy.hot(state)
        guard isHot != hot else { return }
        hot = isHot
        if isHot {
            if mode == .auto {
                coolSwitched = true
                let last = entries.last(where: { $0.provider != "phrasebook" })?.src
                mode = EnergyPolicy.coolMode(pair: pair, lastSpoken: last)
            }
            partial = ""
            Haptics.warning()
            flash("🌡 " + T("hot_single"), seconds: 6)
        } else if coolSwitched {
            coolSwitched = false
            if pair.distinguishable { mode = .auto }
            flash("✅ " + T("cool_again"))
        }
    }

    /// Schnellsätze-Widget: eingebauten Satz (id = Englisch) vorlesen.
    func sayBuiltIn(_ id: String) {
        guard let p = Phrasebook.builtIn.first(where: { $0.en == id }) ?? favorites.first(where: { $0.en == id }) else { return }
        say(p)
    }

    /// Kurzbefehl „Letzte Übersetzung groß zeigen“.
    func showLastBig() {
        bigRequest = visibleEntries.last(where: { $0.translation != nil })?.id
        touch()
    }

    /// Live-Aktivität (Sperrbildschirm, Dynamic Island) auf den aktuellen Stand bringen.
    func liveUpdate() {
        guard liveActivity, isListening else {
            if !liveActivity { LiveActivityController.shared.end() }
            return
        }
        let last = visibleEntries.last { $0.translation != nil }
        let status: ListeningActivityAttributes.Status = paused ? .paused
            : speakingID != nil ? .speaking
            : (pushToTalk && !pttHeld) ? .ready
            : hearing ? .hearing : .listening
        let state = ListeningActivityAttributes.ContentState(
            status: status, statusText: liveStatusText(status),
            source: last?.text ?? "", translation: last?.translation ?? "",
            srcFlag: last?.src.flag ?? pair.mine.flag, dstFlag: last?.target.flag ?? pair.partner.flag)
        LiveActivityController.shared.update(state, pair: "\(pair.mine.flag) ⇄ \(pair.partner.flag)")
    }

    private func liveStatusText(_ s: ListeningActivityAttributes.Status) -> String {
        switch s {
        case .listening: return T("listening")
        case .hearing: return T("hearing")
        case .speaking: return T("speaking")
        case .paused: return T("paused_plain")
        case .ready: return T("ptt_hint")
        }
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
        visibleEntries.map {
            "[\(Self.stamp.string(from: $0.date))] \($0.src.rawValue.uppercased())→\($0.target.rawValue.uppercased()): \($0.text)\n→ \($0.translation ?? "–")"
        }.joined(separator: "\n\n")
    }
}
