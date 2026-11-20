// SpeechEngine.swift – Mikrofon -> Äußerungen. Apples On-Device-Erkennung (SpeechAnalyzer), je Sprache ein
// Erkenner auf demselben Audio; die Sprachwahl trifft das Modell (LanguagePick). Hinter einem Protokoll,
// damit sich Whisper (WhisperEngine.swift) einsetzen lässt. Die Aufnahme selbst steckt in AudioCapture.
import AVFoundation
import Speech
import os

private let log = Logger(subsystem: "dolmetscher", category: "speech")

enum SpeechEvent: Sendable {
    case level(Float)
    case hearing(Bool)
    /// Bisher Erkanntes je Sprache (Live-Vorschau), mit echter Konfidenz.
    case partial([Lang: Hypothesis])
    case utterance([Lang: Hypothesis])
    /// Ein Erkenner ist ausgefallen: die Aufnahme liefert nichts mehr und muss neu gestartet werden.
    case failed(String)
    /// Anruf, Siri, Kopfhörer an/ab: die Aufnahme ist abgerissen und muss neu gestartet werden.
    case interrupted
    /// Anruf o. Ä. beginnt: Aufnahme ruht, bis `interrupted` (Ende) kommt.
    case interruptionBegan
    /// Unterbrechung vorbei, iOS rät aber vom automatischen Weiterhören ab: der Nutzer startet selbst.
    case interruptionEndedNoResume
    /// Kopfhörer/Headset wurde abgezogen: Wiedergabe anhalten, Hinweis zeigen, Aufnahme neu aufbauen.
    case routeLost
    /// Nur ein Ausgabegerät (Kopfhörer ohne Mikrofon) wurde abgezogen: Vorlesen anhalten, Aufnahme läuft weiter.
    case outputRouteLost
    /// Anderes Eingabegerät oder neues Format: Aufnahme neu aufbauen – nicht während einer Unterbrechung.
    case rebuild
}

enum SpeechError: LocalizedError {
    case unsupported(Lang), noModel(Lang), noMicrophone, denied, downloadOffline
    var errorDescription: String? {
        switch self {
        case .unsupported(let l): return T("err_unsupported") + " (\(l.rawValue))"
        case .noModel(let l): return T("err_no_model") + " (\(l.rawValue))"
        case .noMicrophone: return T("err_no_mic")
        case .denied: return T("err_denied")
        case .downloadOffline: return T("err_model_offline")
        }
    }
}

struct AudioOptions: Sendable {
    /// Bluetooth-Headset als Mikrofon zulassen
    var headset = false
    /// 598: Empfindlichkeit der Pausen-Erkennung (Faktor über dem Grundrauschen).
    var sensitivity: Sensitivity = .normal
    /// Gewählter Eingang (UID aus `availableInputs`), nil = automatisch.
    var preferredInput: String?
    /// Echo-/Rauschunterdrückung des Systems (iOS 18.2+), wenn verfügbar.
    var echoCancel = false
}

protocol SpeechEngine: AnyObject, Sendable {
    var events: AsyncStream<SpeechEvent> { get }
    /// `onDownload`: Fortschritt 0…1, solange ein Sprachmodell geladen wird (einmalig je Sprache).
    func start(langs: [Lang], pauseSeconds: Double, options: AudioOptions,
               onDownload: @escaping @Sendable (Lang, Double) -> Void) async throws
    func stop() async
    /// Halbduplex: während der Sprachausgabe wird das Mikrofon verworfen (sonst übersetzt die App sich selbst).
    func setMuted(_ on: Bool)
    func setPause(_ seconds: Double)
    /// Push-to-talk losgelassen: die laufende Äußerung sofort abschließen, ohne auf die Pause zu warten.
    func flush()
}

/// Ein Erkenner für eine Sprache. Zeitachse = Sekunden des ihm zugeführten Audios.
final class LangRecognizer: @unchecked Sendable {
    private struct Piece { var start: Double; var text: String; var conf: Double }

    let lang: Lang
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?
    private var converterSource: AVAudioFormat?
    private let lock = NSLock()
    private var finals: [Piece] = []
    private var volatile: Piece?
    private var fedSeconds = 0.0
    private var consumedUpTo = 0.0
    private var reader: Task<Void, Never>?
    private var shutDown = false
    var isShutDown: Bool { lock.lock(); defer { lock.unlock() }; return shutDown }

    static func locale(for lang: Lang) async -> Locale? {
        let all = await DictationTranscriber.supportedLocales
        return all.first { $0.language.languageCode?.identifier == lang.rawValue && $0.region?.identifier == lang.region }
            ?? all.first { $0.language.languageCode?.identifier == lang.rawValue }
    }

    /// Muss für `langs` noch ein Sprachmodell geladen werden (braucht Internet)?
    static func needsDownload(_ langs: [Lang]) async -> Bool {
        let installed = await DictationTranscriber.installedLocales
        for l in langs {
            guard let loc = await locale(for: l) else { continue }
            if !installed.contains(where: { $0.identifier(.bcp47) == loc.identifier(.bcp47) }) { return true }
        }
        return false
    }

    /// `onError`: der Erkenner ist ausgefallen (nicht beim normalen Beenden).
    init(lang: Lang, onDownload: @escaping @Sendable (Double) -> Void,
         onError: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        log.info("\(lang.rawValue): locale?")
        guard let locale = await Self.locale(for: lang) else { throw SpeechError.unsupported(lang) }
        log.info("\(lang.rawValue): locale \(locale.identifier)")
        let t = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                                     reportingOptions: [.volatileResults],
                                     attributeOptions: [.transcriptionConfidence])
        // Sprachmodell bei Bedarf laden (einmalig, braucht Internet).
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            log.info("\(lang.rawValue): downloading assets")
            let watch = Task {
                while !Task.isCancelled {
                    onDownload(req.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { watch.cancel() }
            // Stopp während des Downloads: sofort zurück (der Download läuft im Hintergrund weiter).
            nonisolated(unsafe) let request = req
            try await abandonable { try await request.downloadAndInstall() }
            onDownload(1)
        }
        log.info("\(lang.rawValue): assets ok")
        guard let f = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else {
            throw SpeechError.noModel(lang)
        }
        let a = SpeechAnalyzer(modules: [t])
        log.info("\(lang.rawValue): format \(f)")
        try await a.prepareToAnalyze(in: f)
        log.info("\(lang.rawValue): prepared")
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        try await a.start(inputSequence: stream)
        log.info("\(lang.rawValue): started")
        self.lang = lang
        analyzer = a
        format = f
        input = cont
        reader = Task { [weak self] in
            do {
                for try await r in t.results {
                    var sum = 0.0, n = 0.0
                    for run in r.text.runs {
                        if let c = run.transcriptionConfidence { sum += c; n += 1 }
                    }
                    self?.absorb(Piece(start: r.range.start.seconds, text: String(r.text.characters),
                                       conf: n > 0 ? sum / n : 0.5), final: r.isFinal)
                }
            } catch is CancellationError {
            } catch {
                // Beim Beenden (shutdown) bricht der Leser ebenfalls ab – das ist kein Ausfall.
                guard let self, !self.isShutDown else { return }
                log.error("\(lang.rawValue): recognizer failed: \(error.localizedDescription, privacy: .public)")
                onError(error.localizedDescription)
            }
        }
    }

    private func absorb(_ p: Piece, final: Bool) {
        lock.lock(); defer { lock.unlock() }
        // Nachzügler zu schon entnommenem oder verworfenem Audio nicht noch einmal liefern.
        guard p.start >= consumedUpTo else { return }
        if final { finals.append(p); volatile = nil } else { volatile = p }
    }

    /// Nur von der Audio-Queue der Engine aufrufen.
    func feed(_ buf: AVAudioPCMBuffer) {
        guard let out = convert(buf) else { return }
        fedSeconds += Double(out.frameLength) / format.sampleRate
        input.yield(AnalyzerInput(buffer: out))
    }

    /// Aktuelle Position auf der Zeitachse (Audio-Queue).
    var position: Double { fedSeconds }

    private func convert(_ buf: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buf.format == format { return buf }
        if converter == nil || converterSource != buf.format {
            converter = AVAudioConverter(from: buf.format, to: format)
            converterSource = buf.format
        }
        guard let converter else { return nil }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * format.sampleRate / buf.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return nil }
        var given = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return buf
        }
        return err == nil && out.frameLength > 0 ? out : nil
    }

    /// Bis zur angegebenen Stelle der eigenen Zeitachse abschließen (nil = alles bisher Verarbeitete).
    func finalize(through seconds: Double? = nil) async {
        let t = seconds.map { CMTime(seconds: $0, preferredTimescale: 48_000) }
        try? await analyzer.finalize(through: t)
    }

    /// Was bisher erkannt wurde, ohne es zu verbrauchen (für die Live-Anzeige), mit mittlerer Konfidenz.
    func peek() -> Hypothesis? {
        lock.lock(); defer { lock.unlock() }
        let parts = finals + (volatile.map { [$0] } ?? [])
        let text = parts.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Hypothesis(text: text, confidence: parts.map(\.conf).reduce(0, +) / Double(parts.count))
    }

    /// Alles, was vor `upTo` begann, entnehmen.
    func take(upTo: Double) -> Hypothesis? {
        lock.lock(); defer { lock.unlock() }
        consumedUpTo = max(consumedUpTo, upTo)
        var parts = finals.filter { $0.start < upTo }
        finals.removeAll { $0.start < upTo }
        if let v = volatile, v.start < upTo { parts.append(v); volatile = nil }
        let text = parts.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Hypothesis(text: text, confidence: parts.map(\.conf).reduce(0, +) / Double(parts.count))
    }

    private func markShutDown() { lock.lock(); shutDown = true; lock.unlock() }

    func shutdown() async {
        markShutDown()
        input.finish()
        await analyzer.cancelAndFinishNow()
        reader?.cancel()
    }
}

final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    let events: AsyncStream<SpeechEvent>
    private let emit: AsyncStream<SpeechEvent>.Continuation
    private var capture: AudioCapture!
    private var queue: DispatchQueue { capture.queue }
    // Zustand nur auf `queue`
    private var recs: [LangRecognizer] = []
    private var muted = false
    private var gate = VoiceGate(pause: 0.8)
    private var sincePartial = 0.0, sinceLevel = 0.0
    private var lastEnd: Task<Void, Never>?
    private var preRoll = FeedPreRoll<AVAudioPCMBuffer>(maxSeconds: 0.7)

    init() {
        (events, emit) = AsyncStream<SpeechEvent>.makeStream(bufferingPolicy: .unbounded)
        let emit = emit
        capture = AudioCapture(onBuffer: { [weak self] in self?.process($0) }, onEvent: { emit.yield($0) })
    }

    func start(langs: [Lang], pauseSeconds: Double, options: AudioOptions,
               onDownload: @escaping @Sendable (Lang, Double) -> Void) async throws {
        try await capture.activate(options: options)
        var made: [LangRecognizer] = []
        do {
            let emit = emit
            // Beide Erkenner gleichzeitig laden – halbiert die Startzeit im Automatik-Modus.
            made = try await withThrowingTaskGroup(of: (Int, LangRecognizer).self) { g in
                for (i, l) in langs.enumerated() {
                    g.addTask {
                        (i, try await LangRecognizer(lang: l, onDownload: { onDownload(l, $0) },
                                                     onError: { emit.yield(.failed($0)) }))
                    }
                }
                var got: [(Int, LangRecognizer)] = []
                do {
                    for try await r in g { got.append(r) }
                } catch {
                    for (_, r) in got { await r.shutdown() }
                    throw error
                }
                return got.sorted { $0.0 < $1.0 }.map(\.1)
            }
            try capture.checkInput()
        } catch {
            for r in made { await r.shutdown() }
            throw error
        }
        queue.sync { recs = made; gate = VoiceGate(pause: pauseSeconds, sensitivity: options.sensitivity); muted = false }
        try capture.begin()
    }

    func stop() async {
        capture.end()
        let old = queue.sync { () -> [LangRecognizer] in let r = recs; recs = []; return r }
        for r in old { await r.shutdown() }
        emit.finish()
        capture.deactivate()
    }

    func setMuted(_ on: Bool) {
        queue.async {
            self.muted = on
            // Reste verwerfen: vor der Ausgabe Gehörtes ist erledigt, danach soll kein Echo hängen bleiben.
            // Abschließen, damit der nächste Satz als neuer Abschnitt beginnt.
            for r in self.recs {
                _ = r.take(upTo: r.position)
                if on { Task { await r.finalize() } }
            }
            self.resetVAD()
        }
    }

    func setPause(_ seconds: Double) { queue.async { self.gate.pause = seconds } }

    func flush() {
        queue.async {
            guard !self.muted, !self.recs.isEmpty else { return }
            let heardSomething = self.gate.inUtterance || self.recs.contains { $0.peek() != nil }
            if self.gate.inUtterance { self.emit.yield(.hearing(false)) }
            self.gate.reset()
            if heardSomething { self.endUtterance() }
        }
    }

    private func resetVAD() {
        preRoll.clear()
        if gate.inUtterance { emit.yield(.hearing(false)) }
        gate.reset()
    }

    private func process(_ buf: AVAudioPCMBuffer) {
        guard !muted, !recs.isEmpty, buf.floatChannelData != nil, buf.frameLength > 0 else { return }
        let rms = AudioCapture.rms(buf)
        let dur = Double(buf.frameLength) / buf.format.sampleRate
        // Pegel für die Anzeige gedrosselt (~12/s), sonst baut die Oberfläche ständig neu auf.
        sinceLevel += dur
        if sinceLevel >= 0.08 { sinceLevel = 0; emit.yield(.level(min(1, rms * 12))) }

        // Stille nicht an die Erkenner füttern (Akku, Wärme): nur Sprache samt kurzem Vorlauf. Die Zeitachse der
        // Erkenner ist die Summe des gefütterten Audios; Marken (`position`) bleiben damit stimmig.
        let event = gate.step(rms: rms, dur: dur)
        if event == .started {
            for b in preRoll.drain() { for r in recs { r.feed(b) } }
        }
        if gate.inUtterance || event == .ended {
            for r in recs { r.feed(buf) }
        } else {
            preRoll.push(buf, dur: dur)
        }
        switch event {
        case .started: emit.yield(.hearing(true))
        case .ended: emit.yield(.hearing(false)); endUtterance(); return
        case nil: break
        }
        guard gate.inUtterance else { return }
        sincePartial += dur
        if sincePartial >= 0.25 {
            sincePartial = 0
            var seen: [Lang: Hypothesis] = [:]
            for r in recs { seen[r.lang] = r.peek() }
            emit.yield(.partial(seen))
        }
    }

    private func endUtterance() {
        let marks = recs.map { ($0, $0.position) }
        let prev = lastEnd
        lastEnd = Task {
            await prev?.value   // Reihenfolge der Äußerungen wahren
            await withTaskGroup(of: Void.self) { g in for (r, mark) in marks { g.addTask { await raceTimeout(seconds: 4) { await r.finalize(through: mark) } } } }
            try? await Task.sleep(for: .milliseconds(120))   // letzte Ergebnisse einsammeln lassen
            // Hat nur ein Erkenner schon Text, kurz auf den anderen warten – sonst gewinnt die
            // schnellere Sprache, nur weil die andere noch rechnet (v. a. Thai beim ersten Satz).
            if marks.count > 1 {
                for _ in 0..<10 {
                    let have = marks.map { $0.0.peek() != nil }
                    if have.allSatisfy({ $0 }) || !have.contains(true) { break }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
            var heard: [Lang: Hypothesis] = [:]
            for (r, mark) in marks { heard[r.lang] = r.take(upTo: mark + 0.05) }
            if !heard.isEmpty { self.emit.yield(.utterance(heard)) }
        }
    }
}

/// Einmal-Schalter für `raceTimeout`.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}

/// Wartet höchstens `seconds` auf `op` – auch wenn `op` auf Abbruch nicht reagiert (ein hängendes `analyzer.finalize`
/// würde sonst alle folgenden Äußerungen blockieren). `op` läuft dann im Hintergrund weiter und wird ignoriert.
func raceTimeout(seconds: Double, _ op: @escaping @Sendable () async -> Void) async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        let once = Once()
        Task { await op(); if once.take() { c.resume() } }
        Task { try? await Task.sleep(for: .seconds(seconds)); if once.take() { c.resume() } }
    }
}

/// Kurzer Vorlauf vor dem Sprachbeginn: Die Pausen-Erkennung merkt den Anfang erst nach `minSpeech` – der Vorlauf stellt sicher,
/// dass der erste Laut nicht fehlt, obwohl Stille gar nicht erst an die Erkenner geht.
struct FeedPreRoll<Item> {
    let maxSeconds: Double
    private var items: [(item: Item, dur: Double)] = []
    private var total = 0.0

    init(maxSeconds: Double) { self.maxSeconds = maxSeconds }

    var seconds: Double { total }
    var count: Int { items.count }

    mutating func push(_ item: Item, dur: Double) {
        items.append((item, dur)); total += dur
        while total > maxSeconds, items.count > 1 { total -= items.removeFirst().dur }
    }

    /// Alles in Aufnahmereihenfolge entnehmen; der Vorlauf ist danach leer.
    mutating func drain() -> [Item] {
        let out = items.map(\.item)
        clear()
        return out
    }

    mutating func clear() { items = []; total = 0 }
}
