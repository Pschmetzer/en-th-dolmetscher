// SpeechEngine.swift – Mikrofon -> Äußerungen. Apples On-Device-Erkennung (SpeechAnalyzer), je Sprache ein
// Erkenner auf demselben Audio; die Sprachwahl trifft das Modell (LanguagePick). Hinter einem Protokoll,
// damit sich später z. B. Whisper einsetzen lässt.
import AVFoundation
import Speech
import os

private let log = Logger(subsystem: "dolmetscher", category: "speech")

enum SpeechEvent: Sendable {
    case level(Float)
    case hearing(Bool)
    case partial(en: String, th: String)
    case utterance(en: Hypothesis?, th: Hypothesis?)
    /// Anruf, Siri, Kopfhörer an/ab: die Aufnahme ist abgerissen und muss neu gestartet werden.
    case interrupted
}

enum SpeechError: LocalizedError {
    case unsupported(Lang), noModel(Lang), noMicrophone, denied
    var errorDescription: String? {
        switch self {
        case .unsupported(let l): return T("err_unsupported") + " (\(l.rawValue))"
        case .noModel(let l): return T("err_no_model") + " (\(l.rawValue))"
        case .noMicrophone: return T("err_no_mic")
        case .denied: return T("err_denied")
        }
    }
}

struct AudioOptions: Sendable {
    /// Bluetooth-Headset als Mikrofon zulassen
    var headset = false
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

    static func locale(for lang: Lang) async -> Locale? {
        let all = await DictationTranscriber.supportedLocales
        let region = lang == .en ? "US" : "TH"
        return all.first { $0.language.languageCode?.identifier == lang.rawValue && $0.region?.identifier == region }
            ?? all.first { $0.language.languageCode?.identifier == lang.rawValue }
    }

    init(lang: Lang, onDownload: @escaping @Sendable (Double) -> Void) async throws {
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
            try await req.downloadAndInstall()
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
            } catch {}
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

    /// Was bisher erkannt wurde, ohne es zu verbrauchen (für die Live-Anzeige).
    func peek() -> String {
        lock.lock(); defer { lock.unlock() }
        return (finals.map(\.text) + [volatile?.text ?? ""]).joined().trimmingCharacters(in: .whitespacesAndNewlines)
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

    func shutdown() async {
        input.finish()
        await analyzer.cancelAndFinishNow()
        reader?.cancel()
    }
}

final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    let events: AsyncStream<SpeechEvent>
    private let emit: AsyncStream<SpeechEvent>.Continuation
    private let audio = AVAudioEngine()
    private let queue = DispatchQueue(label: "dolmetscher.speech")
    // Zustand nur auf `queue`
    private var recs: [LangRecognizer] = []
    private var muted = false
    private var pause = 0.8
    private var noise: Float = 0.004
    private var speechRun = 0.0, silenceRun = 0.0, uttDur = 0.0, sincePartial = 0.0
    private var inUtterance = false
    private var lastEnd: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() { (events, emit) = AsyncStream<SpeechEvent>.makeStream(bufferingPolicy: .bufferingNewest(64)) }

    static func authorize() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        // Die Erkennung läuft auf dem Gerät (SpeechAnalyzer). Die Freigabe wird trotzdem erfragt; ob sie
        // zwingend ist, entscheidet das System beim Start – eine Ablehnung führt dort zu einer Fehlermeldung.
        _ = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        return true
    }

    func start(langs: [Lang], pauseSeconds: Double, options: AudioOptions,
               onDownload: @escaping @Sendable (Lang, Double) -> Void) async throws {
        #if DEBUG
        // Test ohne Mikrofon (der Simulator hat oft keins): Audiodateien statt Mikrofon einspielen.
        if let files = ProcessInfo.processInfo.environment["DOLMETSCHER_AUDIO_FILES"] {
            var made: [LangRecognizer] = []
            for l in langs { made.append(try await LangRecognizer(lang: l) { onDownload(l, $0) }) }
            queue.sync { recs = made; pause = pauseSeconds; muted = false; inUtterance = false }
            Task.detached { [weak self] in await self?.play(files.split(separator: ":").map(String.init)) }
            return
        }
        #endif
        guard await Self.authorize() else { throw SpeechError.denied }
        log.info("authorized")
        let session = AVAudioSession.sharedInstance()
        var opts: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
        if options.headset { opts.insert(.allowBluetoothHFP) }
        try session.setCategory(.playAndRecord, mode: .default, options: opts)
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)
        var made: [LangRecognizer] = []
        do {
            for l in langs { made.append(try await LangRecognizer(lang: l) { onDownload(l, $0) }) }
        } catch {
            for r in made { await r.shutdown() }
            throw error
        }
        let node = audio.inputNode
        let fmt = node.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { throw SpeechError.noMicrophone }
        queue.sync { recs = made; pause = pauseSeconds; muted = false; inUtterance = false }
        node.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buf, _ in
            // Der Puffer gehört dem System und gilt nur im Block: kopieren.
            guard let copy = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: buf.frameLength),
                  let src = buf.floatChannelData, let dst = copy.floatChannelData else { return }
            copy.frameLength = buf.frameLength
            for c in 0..<Int(buf.format.channelCount) {
                dst[c].update(from: src[c], count: Int(buf.frameLength))
            }
            self?.queue.async { self?.process(copy) }
        }
        audio.prepare()
        try audio.start()
        let nc = NotificationCenter.default
        let lost: @Sendable (Notification) -> Void = { [weak self] _ in self?.emit.yield(.interrupted) }
        observers = [
            nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] n in
                let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.emit.yield(.interrupted) }
            },
            nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: nil, using: lost),
            nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil, using: lost),
            // Headset an/ab: neues Eingabeformat, die Aufnahme muss neu aufgebaut werden.
            nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] n in
                let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable { self?.emit.yield(.interrupted) }
            },
        ]
    }

    func stop() async {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if audio.isRunning {
            audio.inputNode.removeTap(onBus: 0)
            audio.stop()
        }
        let old = queue.sync { () -> [LangRecognizer] in let r = recs; recs = []; return r }
        for r in old { await r.shutdown() }
        emit.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    #if DEBUG
    /// Spielt Dateien im Echtzeittakt in dieselbe Verarbeitung wie das Mikrofon, mit Stille dazwischen.
    private func play(_ paths: [String]) async {
        for path in paths {
            guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)),
                  let all = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: all)) != nil, let src = all.floatChannelData else {
                log.error("cannot read \(path)"); continue
            }
            let fmt = file.processingFormat
            let chunk = AVAudioFrameCount(fmt.sampleRate / 10)
            let silence = AVAudioFrameCount(fmt.sampleRate * 7)
            var pos: AVAudioFrameCount = 0
            while pos < all.frameLength + silence {
                guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunk), let dst = buf.floatChannelData else { return }
                buf.frameLength = chunk
                for c in 0..<Int(fmt.channelCount) {
                    for i in 0..<Int(chunk) {
                        let j = Int(pos) + i
                        dst[c][i] = j < Int(all.frameLength) ? src[c][j] : 0
                    }
                }
                pos += chunk
                queue.async { self.process(buf) }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    #endif

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

    func setPause(_ seconds: Double) { queue.async { self.pause = seconds } }

    private func resetVAD() {
        if inUtterance { emit.yield(.hearing(false)) }
        inUtterance = false; speechRun = 0; silenceRun = 0; uttDur = 0
    }

    private func process(_ buf: AVAudioPCMBuffer) {
        guard !muted, !recs.isEmpty, let ch = buf.floatChannelData, buf.frameLength > 0 else { return }
        let n = Int(buf.frameLength)
        var sum: Float = 0
        for i in 0..<n { let v = ch[0][i]; sum += v * v }
        let rms = (sum / Float(n)).squareRoot()
        let dur = Double(n) / buf.format.sampleRate
        for r in recs { r.feed(buf) }
        emit.yield(.level(min(1, rms * 12)))

        // Einfache Sprachpausen-Erkennung über die Lautstärke mit mitlaufendem Grundrauschen.
        if rms > max(0.008, noise * 3.5) {
            speechRun += dur; silenceRun = 0
            if !inUtterance && speechRun >= 0.12 { inUtterance = true; uttDur = 0; emit.yield(.hearing(true)) }
        } else {
            silenceRun += dur; speechRun = 0
            noise = noise * 0.95 + rms * 0.05
        }
        guard inUtterance else { return }
        uttDur += dur; sincePartial += dur
        if sincePartial >= 0.25 {
            sincePartial = 0
            emit.yield(.partial(en: recs.first { $0.lang == .en }?.peek() ?? "",
                                th: recs.first { $0.lang == .th }?.peek() ?? ""))
        }
        if silenceRun >= pause || uttDur > 25 { endUtterance() }
    }

    private func endUtterance() {
        resetVAD()
        let marks = recs.map { ($0, $0.position) }
        let prev = lastEnd
        lastEnd = Task {
            await prev?.value   // Reihenfolge der Äußerungen wahren
            await withTaskGroup(of: Void.self) { g in for (r, mark) in marks { g.addTask { await r.finalize(through: mark) } } }
            try? await Task.sleep(for: .milliseconds(120))   // letzte Ergebnisse einsammeln lassen
            // Hat nur ein Erkenner schon Text, kurz auf den anderen warten – sonst gewinnt die
            // schnellere Sprache, nur weil die andere noch rechnet (v. a. Thai beim ersten Satz).
            if marks.count > 1 {
                for _ in 0..<10 {
                    let have = marks.map { !$0.0.peek().isEmpty }
                    if have.allSatisfy({ $0 }) || !have.contains(true) { break }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
            var en: Hypothesis?, th: Hypothesis?
            for (r, mark) in marks {
                let h = r.take(upTo: mark + 0.05)
                if r.lang == .en { en = h } else { th = h }
            }
            if en != nil || th != nil { self.emit.yield(.utterance(en: en, th: th)) }
        }
    }
}
