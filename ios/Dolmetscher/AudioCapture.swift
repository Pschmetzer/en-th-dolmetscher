// AudioCapture.swift – gemeinsame Mikrofon-Aufnahme für alle Erkenner: Audio-Session, Tap mit Kopie,
// Beobachter für Anruf/Route/Neustart der Mediendienste und (nur DEBUG) Dateiwiedergabe statt Mikrofon.
// Die Puffer kommen auf `queue` an; die Engines halten ihren Zustand auf derselben Queue.
import AVFoundation
import Speech
import os

private let log = Logger(subsystem: "dolmetscher", category: "capture")

final class AudioCapture: @unchecked Sendable {
    let queue = DispatchQueue(label: "dolmetscher.speech")
    private let audio = AVAudioEngine()
    private var observers: [NSObjectProtocol] = []
    private var player: Task<Void, Never>?
    private let onBuffer: (AVAudioPCMBuffer) -> Void
    private let onEvent: @Sendable (SpeechEvent) -> Void

    /// `onBuffer` läuft auf `queue`.
    init(onBuffer: @escaping (AVAudioPCMBuffer) -> Void, onEvent: @escaping @Sendable (SpeechEvent) -> Void) {
        self.onBuffer = onBuffer
        self.onEvent = onEvent
    }

    #if DEBUG
    /// Test ohne Mikrofon (der Simulator hat oft keins): Audiodateien statt Mikrofon einspielen.
    static var debugFiles: [String]? {
        ProcessInfo.processInfo.environment["DOLMETSCHER_AUDIO_FILES"].map { $0.split(separator: ":").map(String.init) }
    }
    #else
    static var debugFiles: [String]? { nil }
    #endif

    static func authorize() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        // Die Erkennung läuft auf dem Gerät (SpeechAnalyzer). Die Freigabe wird trotzdem erfragt; ob sie
        // zwingend ist, entscheidet das System beim Start – eine Ablehnung führt dort zu einer Fehlermeldung.
        _ = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        return true
    }

    /// Schritt 1: Freigabe und Audio-Session (vor dem Laden der Erkenner).
    func activate(options: AudioOptions) async throws {
        if Self.debugFiles != nil { return }
        guard await Self.authorize() else { throw SpeechError.denied }
        log.info("authorized")
        let session = AVAudioSession.sharedInstance()
        var opts: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
        if options.headset { opts.insert(.allowBluetoothHFP) }
        try session.setCategory(.playAndRecord, mode: .default, options: opts)
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)
    }

    /// Prüft, ob ein Mikrofon da ist (nach `activate`, vor dem Laden teurer Modelle sinnvoll).
    func checkInput() throws {
        if Self.debugFiles != nil { return }
        let fmt = audio.inputNode.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { throw SpeechError.noMicrophone }
    }

    /// Schritt 2: Puffer liefern (Tap + Beobachter bzw. Dateien).
    func begin() throws {
        #if DEBUG
        if let files = Self.debugFiles {
            player = Task.detached { [weak self] in await self?.play(files) }
            return
        }
        #endif
        let node = audio.inputNode
        let fmt = node.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { throw SpeechError.noMicrophone }
        node.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buf, _ in
            // Der Puffer gehört dem System und gilt nur im Block: kopieren.
            guard let copy = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: buf.frameLength),
                  let src = buf.floatChannelData, let dst = copy.floatChannelData else { return }
            copy.frameLength = buf.frameLength
            for c in 0..<Int(buf.format.channelCount) {
                dst[c].update(from: src[c], count: Int(buf.frameLength))
            }
            self?.queue.async { self?.onBuffer(copy) }
        }
        audio.prepare()
        try audio.start()
        let emit = onEvent
        let nc = NotificationCenter.default
        let lost: @Sendable (Notification) -> Void = { _ in emit(.interrupted) }
        observers = [
            nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { n in
                let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if raw == AVAudioSession.InterruptionType.began.rawValue { emit(.interruptionBegan) }
                if raw == AVAudioSession.InterruptionType.ended.rawValue { emit(.interrupted) }
            },
            nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: nil, using: lost),
            nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil, using: lost),
            // Headset an/ab: neues Eingabeformat, die Aufnahme muss neu aufgebaut werden.
            nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { n in
                let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable { emit(.interrupted) }
            },
        ]
    }

    /// Aufnahme anhalten (Tap, Beobachter, Dateiwiedergabe). Die Session gibt `deactivate` frei.
    func end() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        player?.cancel()
        player = nil
        if audio.isRunning {
            audio.inputNode.removeTap(onBus: 0)
            audio.stop()
        }
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Effektivwert des ersten Kanals.
    static func rms(_ buf: AVAudioPCMBuffer) -> Float {
        guard let ch = buf.floatChannelData, buf.frameLength > 0 else { return 0 }
        let n = Int(buf.frameLength)
        var sum: Float = 0
        for i in 0..<n { let v = ch[0][i]; sum += v * v }
        return (sum / Float(n)).squareRoot()
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
                if Task.isCancelled { return }
                guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunk), let dst = buf.floatChannelData else { return }
                buf.frameLength = chunk
                for c in 0..<Int(fmt.channelCount) {
                    for i in 0..<Int(chunk) {
                        let j = Int(pos) + i
                        dst[c][i] = j < Int(all.frameLength) ? src[c][j] : 0
                    }
                }
                pos += chunk
                queue.async { self.onBuffer(buf) }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    #endif
}
