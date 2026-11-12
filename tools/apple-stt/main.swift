// apple-stt: transkribiert WAV-Dateien mit Apples On-Device-Erkennung
// (Speech-Framework, macOS 26: DictationTranscriber + SpeechAnalyzer).
//
//   apple-stt --locale th-TH [--realtime] [--preset long|short|progressive] [--out f.json] a.wav b.wav …
//   apple-stt --status            # Berechtigung + Sprach-Assets anzeigen, nichts laden
//
// Ausgabe: pro Datei ein JSON-Objekt (bei mehreren Dateien ein Array):
//   {"file", "text", "ms_total", "ms_first_result", "ms_after_audio_end", "ms_done_after_audio_end",
//    "ms_prepare", "audio_s", "error"}
// --realtime spielt das Audio in 100-ms-Stücken in Echtzeit ein (wie ein Mikrofon). Dann ist
// ms_after_audio_end die Zeit vom letzten eingespielten Stück bis zum letzten endgültigen Ergebnis.
// Ohne --realtime wird die Datei so schnell wie möglich eingespielt (ms_after_audio_end ≈ ms_total).
// Assets werden NIE heruntergeladen.

import AVFoundation
import Foundation
import Speech

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

func statusName(_ s: AssetInventory.Status) -> String {
    switch s {
    case .unsupported: return "unsupported"
    case .supported: return "supported (nicht installiert)"
    case .downloading: return "downloading"
    case .installed: return "installed"
    @unknown default: return "unknown"
    }
}

func authName(_ s: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch s {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .authorized: return "authorized"
    @unknown default: return "unknown"
    }
}

struct Options {
    var locale = "th-TH"
    var realtime = false
    var preset = "long"
    var out: String?
    var status = false
    var requestAuth = false
    var skipAssetCheck = false
    var files: [String] = []
}

func parseArgs() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--locale": o.locale = it.next() ?? o.locale
        case "--realtime": o.realtime = true
        case "--preset": o.preset = it.next() ?? o.preset
        case "--out": o.out = it.next()
        case "--status": o.status = true
        case "--request-auth": o.requestAuth = true
        case "--skip-asset-check": o.skipAssetCheck = true
        default: o.files.append(a)
        }
    }
    return o
}

func makeTranscriber(_ locale: Locale, _ preset: String) -> DictationTranscriber {
    // Volatile Ergebnisse an, damit ms_first_result aussagekräftig ist; Satzzeichen an (wie Whisper).
    let hints: Set<DictationTranscriber.ContentHint> = preset == "short" ? [.shortForm] : []
    var reporting: Set<DictationTranscriber.ReportingOption> = [.volatileResults]
    if preset == "progressive" { reporting.insert(.frequentFinalization) }
    return DictationTranscriber(locale: locale, contentHints: hints,
                                transcriptionOptions: [.punctuation],
                                reportingOptions: reporting, attributeOptions: [])
}

func loadPCM(_ path: String, to fmt: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let src = file.processingFormat
    guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw NSError(domain: "apple-stt", code: 1, userInfo: [NSLocalizedDescriptionKey: "Puffer"])
    }
    try file.read(into: inBuf)
    if src == fmt { return inBuf }
    guard let conv = AVAudioConverter(from: src, to: fmt) else {
        throw NSError(domain: "apple-stt", code: 2, userInfo: [NSLocalizedDescriptionKey: "Konverter \(src) -> \(fmt)"])
    }
    let cap = AVAudioFrameCount(Double(inBuf.frameLength) * fmt.sampleRate / src.sampleRate) + 1024
    let outBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap)!
    var done = false
    var err: NSError?
    conv.convert(to: outBuf, error: &err) { _, status in
        if done { status.pointee = .endOfStream; return nil }
        done = true; status.pointee = .haveData; return inBuf
    }
    if let err { throw err }
    return outBuf
}

func slice(_ buf: AVAudioPCMBuffer, from: AVAudioFrameCount, count: AVAudioFrameCount) -> AVAudioPCMBuffer {
    let fmt = buf.format
    let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: count)!
    out.frameLength = count
    let bpf = Int(fmt.streamDescription.pointee.mBytesPerFrame)
    let srcList = UnsafeMutableAudioBufferListPointer(buf.mutableAudioBufferList)
    let dstList = UnsafeMutableAudioBufferListPointer(out.mutableAudioBufferList)
    for i in 0..<srcList.count {
        let s = srcList[i].mData!.advanced(by: Int(from) * bpf)
        memcpy(dstList[i].mData!, s, Int(count) * bpf)
    }
    return out
}

final class Box: @unchecked Sendable {
    var firstResult: Double?
    var lastFinal: Double?
    var finals: [String] = []
    var lastVolatile = ""
}

func transcribe(_ path: String, _ o: Options) async -> [String: Any] {
    var r: [String: Any] = ["file": path]
    do {
        let transcriber = makeTranscriber(Locale(identifier: o.locale), o.preset)
        let tPrep0 = now()
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            r["error"] = "kein Audioformat (Assets fehlen?)"; return r
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: fmt)
        r["ms_prepare"] = (now() - tPrep0).rounded()

        let pcm = try loadPCM(path, to: fmt)
        let total = pcm.frameLength
        r["audio_s"] = Double(total) / fmt.sampleRate

        let box = Box()
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        let t0 = now()
        let collector = Task {
            for try await res in transcriber.results {
                let t = now()
                if box.firstResult == nil { box.firstResult = t }
                let s = String(res.text.characters)
                if res.isFinal { box.finals.append(s); box.lastFinal = t; box.lastVolatile = "" }
                else { box.lastVolatile = s }
            }
            return now()
        }
        try await analyzer.start(inputSequence: stream)

        let chunk = AVAudioFrameCount(fmt.sampleRate / 10)  // 100 ms
        var pos: AVAudioFrameCount = 0
        while pos < total {
            let n = min(chunk, total - pos)
            cont.yield(AnalyzerInput(buffer: slice(pcm, from: pos, count: n)))
            pos += n
            if o.realtime {
                let due = t0 + Double(pos) / fmt.sampleRate * 1000
                let wait = due - now()
                if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e6)) }
            }
        }
        let tEnd = now()
        cont.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let tDone = try await collector.value

        var text = box.finals.joined()
        if text.isEmpty { text = box.lastVolatile }
        r["text"] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        r["ms_total"] = (tDone - t0).rounded()
        r["ms_first_result"] = box.firstResult.map { ($0 - t0).rounded() } ?? NSNull()
        r["ms_after_audio_end"] = box.lastFinal.map { max(0, $0 - tEnd).rounded() } ?? NSNull()
        r["ms_done_after_audio_end"] = (tDone - tEnd).rounded()
    } catch {
        r["error"] = "\(error)"
    }
    return r
}

func emit(_ obj: Any, _ out: String?) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    if let out { try! data.write(to: URL(fileURLWithPath: out)) }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

let opts = parseArgs()

if opts.requestAuth {
    // Nur auf ausdrücklichen Wunsch: kann einen Systemdialog auslösen.
    let sem = DispatchSemaphore(value: 0)
    SFSpeechRecognizer.requestAuthorization { s in
        FileHandle.standardError.write("Berechtigung: \(authName(s))\n".data(using: .utf8)!); sem.signal()
    }
    sem.wait()
}

if opts.status {
    var info: [String: Any] = ["speech_auth": authName(SFSpeechRecognizer.authorizationStatus())]
    let sup = await DictationTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
    let inst = await DictationTranscriber.installedLocales.map { $0.identifier(.bcp47) }
    info["dictation_supported"] = sup.filter { $0.hasPrefix("th") || $0.hasPrefix("en-US") }
    info["dictation_installed"] = inst
    info["speech_installed"] = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
    var st: [String: String] = [:]
    for l in ["th-TH", "en-US"] {
        st[l] = statusName(await AssetInventory.status(forModules: [makeTranscriber(Locale(identifier: l), "long")]))
    }
    info["asset_status"] = st
    emit(info, opts.out)
    exit(0)
}

if opts.files.isEmpty {
    FileHandle.standardError.write("Aufruf: apple-stt --locale th-TH [--realtime] [--out f.json] a.wav …\n".data(using: .utf8)!)
    exit(2)
}

let st = await AssetInventory.status(forModules: [makeTranscriber(Locale(identifier: opts.locale), opts.preset)])
if st != .installed && !opts.skipAssetCheck {
    emit(["error": "Sprach-Assets für \(opts.locale): \(statusName(st)). Nicht heruntergeladen. "
          + "Installation: Systemeinstellungen > Tastatur > Diktat > Sprache hinzufügen."], opts.out)
    exit(3)
}

var all: [[String: Any]] = []
for f in opts.files { all.append(await transcribe(f, opts)) }
emit(opts.files.count == 1 ? all[0] : all, opts.out)
