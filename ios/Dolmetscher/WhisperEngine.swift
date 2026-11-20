// WhisperEngine.swift – optionale zweite Spracherkennung mit WhisperKit (on-device, Core ML).
// Aufnahme über AudioCapture, Sprachpausen über VoiceGate; jede Äußerung (mit Pre-Roll) wird als Ganzes
// erkannt: erst Sprache (nur en/th), dann Transkription mit erzwungener Sprache. Modelle lädt der Nutzer
// selbst in den Einstellungen (WhisperStore) – ohne Modell bleibt die App bei Apples Erkennung.
import AVFoundation
import Observation
import UIKit
import WhisperKit
import os

private let log = Logger(subsystem: "dolmetscher", category: "whisper")

enum WhisperFailure: LocalizedError {
    case noModel, loadFailed(String)
    var errorDescription: String? {
        switch self {
        case .noModel: return T("whisper_no_model")
        case .loadFailed(let s): return T("whisper_load_failed") + " (\(s))"
        }
    }
}

/// Ablage der Whisper-Modelle (Application Support, nicht im Backup) und Download/Löschen.
@MainActor @Observable
final class WhisperStore {
    static let shared = WhisperStore()

    /// Einstellung: Whisper statt Apple-Erkennung.
    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "whisperEnabled") } }
    /// Gewähltes Modell (Variante aus argmaxinc/whisperkit-coreml).
    var selected: String { didSet { UserDefaults.standard.set(selected, forKey: "whisperModel") } }
    /// Fortschritt 0…1 während eines Downloads.
    var progress: Double?
    var error: String?
    /// Mobilfunk/Hotspot: der Download wartet auf eine ausdrückliche Freigabe (große Datei).
    var cellularPending = false
    private(set) var installed: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    nonisolated static let repo = "argmaxinc/whisperkit-coreml"

    nonisolated static var base: URL {
        URL.applicationSupportDirectory.appending(path: "whisper", directoryHint: .isDirectory)
    }

    nonisolated static func folder(_ variant: String) -> URL {
        base.appending(path: "models/\(repo)/\(variant)", directoryHint: .isDirectory)
    }

    /// Unterstützte Modelle dieses Geräts (lokale Tabelle von WhisperKit, kein Netz).
    let choices: [String]
    let recommended: String?

    init() {
        let support = WhisperKit.recommendedModels()
        choices = WhisperCatalog.choices(supported: support.supported)
        recommended = WhisperCatalog.defaultModel(recommended: support.default, supported: support.supported)
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "whisperEnabled")
        selected = d.string(forKey: "whisperModel") ?? recommended ?? "openai_whisper-base"
        installed = d.string(forKey: "whisperInstalled")
        if let i = installed, !Self.isComplete(i) { installed = nil; d.removeObject(forKey: "whisperInstalled") }
        log.info("supported: \(support.supported.joined(separator: ","), privacy: .public) default: \(support.default, privacy: .public)")
    }

    nonisolated static func isComplete(_ variant: String) -> Bool {
        let f = folder(variant)
        // `.incomplete` liegt, solange ein Download läuft oder abgebrochen wurde (halbe Ordner zählen nicht als Modell).
        guard !FileManager.default.fileExists(atPath: marker(variant).path) else { return false }
        return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: f.appending(path: $0).path)
        }
    }

    nonisolated static func marker(_ variant: String) -> URL { folder(variant).appending(path: ".incomplete") }

    /// Freier Speicher für wichtige Daten (Bytes), nil wenn unbekannt.
    nonisolated static func freeBytes() -> Int64? {
        let v = try? URL.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }

    /// Modell, das die Engine laden soll – nur wenn vollständig vorhanden.
    var ready: String? { installed.flatMap { Self.isComplete($0) ? $0 : nil } }

    var downloading: Bool { progress != nil }

    func download(allowCellular: Bool = false) {
        guard task == nil else { return }
        if OfflineMode.setting() { error = T("off_blocked"); return }
        let variant = selected
        error = nil
        cellularPending = false
        if let need = WhisperSize.requiredBytes(sizeMB: WhisperCatalog.sizeMB(variant)), let free = Self.freeBytes(), free < need {
            error = String(format: T("whisper_no_space"), Int(need / 1_000_000))
            return
        }
        if NetStatus.shared.expensive && !allowCellular { cellularPending = true; return }
        progress = 0
        // Läuft der Download, wenn die App in den Hintergrund geht, bekommt er noch ein paar Sekunden Gnadenfrist.
        let bg = BackgroundGrace(name: "whisper-download")
        task = Task {
            defer { task = nil; progress = nil; bg.end() }
            do {
                try Self.prepareBase()
                try? FileManager.default.createDirectory(at: Self.folder(variant), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: Self.marker(variant).path, contents: Data())
                _ = try await WhisperKit.download(variant: variant, downloadBase: Self.base, from: Self.repo) { p in
                    let f = p.fractionCompleted
                    Task { @MainActor in if self.progress != nil { self.progress = min(0.95, f * 0.95) } }
                }
                try Task.checkCancellation()
                // Einmal laden: holt den Tokenizer (sonst bräuchte der erste Start Internet) und lässt
                // Core ML das Modell für dieses Gerät vorbereiten.
                let kit = try await WhisperKit(Self.config(variant, download: true))
                await kit.unloadModels()
                try? FileManager.default.removeItem(at: Self.marker(variant))   // erst nach erfolgreichem Testladen
                if let old = installed, old != variant { try? FileManager.default.removeItem(at: Self.folder(old)) }
                installed = variant
                UserDefaults.standard.set(variant, forKey: "whisperInstalled")
                try? Self.excludeFromBackup()
            } catch is CancellationError {
            } catch {
                log.error("download failed: \(error.localizedDescription, privacy: .public)")
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() { task?.cancel() }

    /// Alles löschen: Modelle, Tokenizer, Hub-Zwischenspeicher.
    func deleteAll() {
        task?.cancel()
        WhisperKitCache.shared.evict()
        try? FileManager.default.removeItem(at: Self.base)
        installed = nil
        UserDefaults.standard.removeObject(forKey: "whisperInstalled")
    }

    nonisolated static func config(_ variant: String, download: Bool) -> WhisperKitConfig {
        WhisperKitConfig(model: variant, downloadBase: base, modelRepo: repo,
                         modelFolder: download ? nil : folder(variant).path,
                         tokenizerFolder: base,
                         verbose: false, logLevel: .error,
                         prewarm: false, load: true, download: download)
    }

    nonisolated private static func prepareBase() throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try excludeFromBackup()
    }

    nonisolated private static func excludeFromBackup() throws {
        var url = base
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try url.setResourceValues(v)
    }
}

final class WhisperSpeechEngine: SpeechEngine, @unchecked Sendable {
    let events: AsyncStream<SpeechEvent>
    private let emit: AsyncStream<SpeechEvent>.Continuation
    private var capture: AudioCapture!
    private var queue: DispatchQueue { capture.queue }
    private let variant: String
    private var kit: WhisperKit?
    private var worker: Task<Void, Never>?
    private let jobs: AsyncStream<Job>.Continuation
    private let jobStream: AsyncStream<Job>

    /// Höchstlänge einer Äußerung (Whisper verarbeitet 30-s-Fenster).
    static let maxSeconds = 28.0
    static let preRollSeconds = 0.4
    /// Wartende Äußerungen, bevor die ältesten verworfen werden.
    static let maxQueuedJobs = 2
    /// So viele Erkennungsfehler in Folge gelten als Ausfall (Oberfläche zeigt dann einen Fehler, Neustart läuft).
    static let maxConsecutiveFailures = 3
    private var failures = 0   // nur im Worker

    struct Job: Sendable { var samples: [Float] }

    // Zustand nur auf `queue`
    private var langs: [Lang] = []
    private var muted = false
    private var running = false
    private var gate = VoiceGate(pause: 0.8)
    private var sinceLevel = 0.0
    private var preRoll = PreRoll(seconds: preRollSeconds)
    private var utterance: [Float] = []
    private let resampler = Resampler16k()

    init(variant: String) {
        self.variant = variant
        (events, emit) = AsyncStream<SpeechEvent>.makeStream(bufferingPolicy: .unbounded)
        // Begrenzt: ist das Modell langsamer als die Sprache, fallen die ältesten Äußerungen weg statt minutenlang
        // aufzulaufen (wie `SpeechBacklog` bei Apple).
        (jobStream, jobs) = AsyncStream<Job>.makeStream(bufferingPolicy: .bufferingNewest(Self.maxQueuedJobs))
        let emit = emit
        capture = AudioCapture(onBuffer: { [weak self] in self?.process($0) }, onEvent: { emit.yield($0) })
        gate.maxUtterance = Self.maxSeconds - Self.preRollSeconds - 0.5
    }

    func start(langs: [Lang], pauseSeconds: Double, options: AudioOptions,
               onDownload: @escaping @Sendable (Lang, Double) -> Void) async throws {
        guard WhisperStore.isComplete(variant) else { throw WhisperFailure.noModel }
        // Modell vor dem Mikrofon laden: scheitert es, läuft nichts und die App fällt auf Apple zurück.
        let k: WhisperKit
        do {
            // Geladenes Modell weiterverwenden: Neustarts (Moduswechsel, Kopfhörer) laden sonst jedes Mal mehrere Sekunden.
            if let cached = WhisperKitCache.shared.take(variant) {
                k = cached
            } else {
                k = try await WhisperKit(WhisperStore.config(variant, download: false))
                WhisperKitCache.shared.put(k, variant: variant)
            }
        } catch {
            log.error("load failed: \(error.localizedDescription, privacy: .public)")
            throw WhisperFailure.loadFailed(error.localizedDescription)
        }
        kit = k
        try await capture.activate(options: options)
        try capture.checkInput()
        queue.sync {
            self.langs = langs; gate.pause = pauseSeconds; gate.apply(options.sensitivity); muted = false; running = true
            preRoll.clear(); utterance = []
        }
        let stream = jobStream
        // Eine Äußerung nach der anderen, in Reihenfolge, außerhalb der Audio-Queue.
        worker = Task.detached { [weak self] in
            for await job in stream {
                guard let self else { return }
                await self.recognize(job, kit: k, langs: langs)
            }
        }
        try capture.begin()
    }

    func stop() async {
        capture.end()
        queue.sync { running = false; utterance = []; preRoll.clear() }
        jobs.finish()
        worker?.cancel()
        await worker?.value
        // Nicht sofort entladen: ein Neustart gleich danach nimmt das Modell wieder (Entladen nach 60 s Ruhe).
        if kit != nil { WhisperKitCache.shared.idle() }
        kit = nil
        emit.finish()
        capture.deactivate()
    }

    func setMuted(_ on: Bool) {
        queue.async {
            self.muted = on
            // Reste verwerfen: Gehörtes vor/während der Ausgabe soll nicht als neue Äußerung erscheinen.
            self.utterance = []
            self.preRoll.clear()
            self.resampler.reset()
            if self.gate.inUtterance { self.emit.yield(.hearing(false)) }
            self.gate.reset()
        }
    }

    func setPause(_ seconds: Double) { queue.async { self.gate.pause = seconds } }

    func flush() {
        queue.async {
            guard self.running, !self.muted, self.gate.inUtterance else { return }
            self.gate.reset()
            self.emit.yield(.hearing(false))
            let u = self.utterance
            self.utterance = []
            if !u.isEmpty { self.jobs.yield(Job(samples: u)) }
        }
    }

    private func process(_ buf: AVAudioPCMBuffer) {
        guard running, !muted, buf.frameLength > 0 else { return }
        let rms = AudioCapture.rms(buf)
        let dur = Double(buf.frameLength) / buf.format.sampleRate
        let samples = resampler.convert(buf)
        sinceLevel += dur
        if sinceLevel >= 0.08 { sinceLevel = 0; emit.yield(.level(min(1, rms * 12))) }

        let ev = gate.step(rms: rms, dur: dur)
        if ev == .started {
            utterance = preRoll.drain()
            emit.yield(.hearing(true))
            emit.yield(.partial([:]))   // keine Teiltexte: Whisper erkennt erst am Ende
        }
        if gate.inUtterance || ev == .ended {
            utterance.append(contentsOf: samples)
        } else {
            preRoll.append(samples)
        }
        if ev == .ended || (gate.inUtterance && utterance.count >= Int(Self.maxSeconds * Resampler16k.rate)) {
            if ev != .ended { gate.reset() }
            emit.yield(.hearing(false))
            let u = utterance
            utterance = []
            if !u.isEmpty { jobs.yield(Job(samples: u)) }
        }
    }

    private func recognize(_ job: Job, kit: WhisperKit, langs: [Lang]) async {
        let duration = Double(job.samples.count) / Resampler16k.rate
        let rms = job.samples.isEmpty ? 0 : (job.samples.reduce(0) { $0 + $1 * $1 } / Float(job.samples.count)).squareRoot()
        do {
            func run(_ l: Lang) async throws -> [TranscriptionResult] {
                let opts = DecodingOptions(language: l.rawValue, temperatureFallbackCount: 3,
                                           usePrefillPrompt: true, detectLanguage: false, skipSpecialTokens: true,
                                           withoutTimestamps: true, compressionRatioThreshold: 2.4,
                                           logProbThreshold: -1.0, noSpeechThreshold: 0.6)
                return try await kit.transcribe(audioArray: job.samples, decodeOptions: opts)
            }
            func score(_ r: [TranscriptionResult]) -> Double {
                let segs = r.flatMap(\.segments)
                return segs.isEmpty ? -.infinity : segs.map { Double($0.avgLogprob) }.reduce(0, +) / Double(segs.count)
            }
            var lang = langs.first ?? .en
            var results: [TranscriptionResult]
            if langs.count > 1 {
                let (top, probs) = try await kit.detectLangauge(audioArray: job.samples)
                if let l = WhisperLang.choose(probs: probs, langs: langs) {
                    lang = l
                    results = try await run(l)
                } else {
                    // Keine Sprache des Paars erkannt (z. B. Lao statt Thai): jede probehalber erzwingen.
                    var tries: [(Lang, [TranscriptionResult])] = []
                    for l in langs { tries.append((l, try await run(l))) }
                    lang = WhisperLang.best(scores: tries.map { ($0.0, score($0.1)) }) ?? lang
                    results = tries.first { $0.0 == lang }?.1 ?? []
                }
                log.info("lang detected \(top, privacy: .public) -> \(lang.rawValue, privacy: .public)")
            } else {
                results = try await run(lang)
            }
            let raw = results.map(\.text).joined(separator: " ")
            let segs = results.flatMap(\.segments)
            lang = WhisperLang.resolve(reported: results.first?.language, chosen: lang, langs: langs)
            guard let text = Hallucination.clean(raw, duration: duration, rms: rms,
                                                 compressionRatios: segs.map { Double($0.compressionRatio) }) else {
                log.info("dropped \(lang.rawValue, privacy: .public): \(raw, privacy: .private)")
                return
            }
            let conf = segs.isEmpty ? 0.5 : exp(segs.map { Double($0.avgLogprob) }.reduce(0, +) / Double(segs.count))
            let h = Hypothesis(text: text, confidence: conf)
            failures = 0
            emit.yield(.utterance([lang: h]))
        } catch {
            log.error("transcribe failed: \(error.localizedDescription, privacy: .public)")
            failures += 1
            if failures >= Self.maxConsecutiveFailures {
                failures = 0
                emit.yield(.failed("Whisper: " + error.localizedDescription))
            }
        }
    }
}

/// Hält das zuletzt geladene Whisper-Modell kurz im Speicher (Neustart ohne Neuladen) und gibt es bei Ruhe oder
/// Speicherwarnung frei.
final class WhisperKitCache: @unchecked Sendable {
    static let shared = WhisperKitCache()
    static let idleSeconds = 60.0
    private let lock = NSLock()
    private var kit: WhisperKit?
    private var variant: String?
    private var generation = 0

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.evict()
        }
    }

    /// Das gemerkte Modell dieser Variante (und ein laufendes Entladen abbrechen), sonst nil.
    func take(_ v: String) -> WhisperKit? {
        lock.withLock {
            generation += 1
            return variant == v ? kit : nil
        }
    }

    func put(_ k: WhisperKit, variant v: String) {
        let old: WhisperKit? = lock.withLock { generation += 1; let o = kit; kit = k; variant = v; return o === k ? nil : o }
        if let old { Task { await old.unloadModels() } }
    }

    func idle() {
        let g: Int = lock.withLock { generation += 1; return generation }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.idleSeconds) { [weak self] in
            guard let self, self.lock.withLock({ self.generation == g }) else { return }
            self.evict()
        }
    }

    func evict() {
        let k: WhisperKit? = lock.withLock { generation += 1; let o = kit; kit = nil; variant = nil; return o }
        if let k { Task { await k.unloadModels() } }
    }
}
