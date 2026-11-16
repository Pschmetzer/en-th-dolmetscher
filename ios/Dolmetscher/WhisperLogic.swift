// WhisperLogic.swift – reine Teile der Whisper-Erkennung ohne WhisperKit-Typen (unit-getestet):
// Sprachwahl en/th, Halluzinationsfilter (wie dolmetscher.py), Pre-Roll-Puffer, Umrechnung auf 16 kHz.
import AVFoundation
import Foundation

enum WhisperLang {
    /// Wahl zwischen den aktiven Sprachen. Nur en/th zählen – Whisper kennt ~100 Sprachen und hält Thai
    /// gern für Lao oder Khmer. Ist nur eine Sprache aktiv, gilt immer sie.
    static func choose(probs: [String: Float], langs: [Lang]) -> Lang {
        guard langs.count > 1 else { return langs.first ?? .en }
        let en = probs[Lang.en.rawValue] ?? 0
        let th = probs[Lang.th.rawValue] ?? 0
        return th > en ? .th : .en
    }

    /// Hat das Transkript selbst eine erlaubte Sprache gemeldet, gilt sie; sonst die vorher gewählte.
    static func resolve(reported: String?, chosen: Lang, langs: [Lang]) -> Lang {
        if let r = reported.flatMap(Lang.init(rawValue:)), langs.contains(r) { return r }
        return chosen
    }
}

/// Typische Whisper-Halluzinationen bei Stille/Rauschen – gleiche Regeln wie `looks_hallucinated`,
/// `JUNK`/`JUNK_IF_SHORT` und `squash_repeats` in dolmetscher.py.
enum Hallucination {
    static let junk = [
        "thank you for watching", "thanks for watching", "subtitles by", "ขอบคุณที่รับชม",
        "thank you very much for watching", "please subscribe",
        "like and subscribe", "subtitles by the amara.org community",
        "ขอบคุณครับ ที่รับชม", "ฝากกดติดตาม", "กดติดตามด้วยนะคะ", "สวัสดีครับ ยินดีต้อนรับสู่ช่อง",
        "ซับไตเติ้ลโดย",
        "thanks for watching and see you next time", "see you in the next video",
        "subscribe to my channel", "please like and subscribe",
        "ขอบคุณที่ติดตามรับชม", "ขอบคุณที่ติดตาม", "ขอบคุณที่รับชมครับ", "อย่าลืมกดไลค์ กดแชร์",
        "อย่าลืมกดไลค์ กดแชร์ กดติดตาม", "อย่าลืมกดไลค์", "อย่าลืมกดติดตาม", "กดไลค์ กดแชร์ กดติดตาม",
        "ฝากกดไลค์ กดแชร์ กดติดตาม",
    ]
    /// Nur bei sehr leiser, kurzer Aufnahme verdächtig.
    static let junkIfShort: Set<String> = ["thank you", "you", "bye", "ขอบคุณครับ", "ขอบคุณค่ะ"]
    private static let tails = ["นะครับ", "นะคะ", "ครับ", "ค่ะ", "คะ", "นะ", "จ้า", "ด้วย", "ทุกคน",
                                "everyone", "guys", "so much", "very much"]

    /// Klein, ohne Satzzeichen und Leerraum (Thai schreibt ohnehin ohne Leerzeichen).
    static func norm(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { u in
            (0x0E00...0x0E7F).contains(u.value) || (u.properties.isAlphabetic || u.properties.numericType != nil)
        }.map(Character.init))
    }

    private static let junkRx: NSRegularExpression = {
        let esc = { (s: String) in NSRegularExpression.escapedPattern(for: norm(s)) }
        let core = junk.map(norm).filter { !$0.isEmpty }.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let tail = tails.map(esc).joined(separator: "|")
        return try! NSRegularExpression(pattern: "^(?:\(core))(?:\(tail))*$")
    }()

    /// Ganze Äußerung ist eine Floskel (höchstens mit Höflichkeits-Anhang) – nie als Präfix.
    static func isJunk(_ text: String) -> Bool {
        let n = norm(text)
        guard !n.isEmpty else { return false }
        return junkRx.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    /// [Music], (Applaus), ♪ … entfernen – das sind keine Wörter.
    static func stripMarkers(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)|[♪♫]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Wiederholungsschleifen kürzen: 'ฮ่าาาาาา' -> 'ฮ่าาา', 'ha ha ha ha ha' -> 'ha ha ha'.
    static func squashRepeats(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"(\D)\1{3,}"#, with: "$1$1$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(.{2,12}?)(?:\s*\1){3,}"#, with: "$1 $1 $1", options: .regularExpression)
        return t
    }

    /// Grund, falls es nach Halluzination aussieht, sonst nil.
    static func looksHallucinated(_ text: String, duration: Double, compressionRatios: [Double]) -> String? {
        if compressionRatios.contains(where: { $0 > 2.6 }) { return "repeat" }
        let chars = text.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        if duration > 0, Double(chars) / duration > 30 { return "too fast" }   // selbst schnelles Thai < ~20/s
        return nil
    }

    /// Gesamter Filter: bereinigter Text oder nil (verwerfen).
    static func clean(_ raw: String, duration: Double, rms: Float, compressionRatios: [Double]) -> String? {
        var text = stripMarkers(raw)
        let squashed = squashRepeats(text)
        let didSquash = squashed != text
        text = squashed
        if let why = looksHallucinated(text, duration: duration, compressionRatios: compressionRatios),
           !(why == "repeat" && didSquash) { return nil }   // Schleife schon gekürzt: Rest ist echter Text
        let low = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if isJunk(text) { return nil }
        if junkIfShort.contains(low), rms < 0.01, duration < 1.5 { return nil }
        return text.isEmpty ? nil : text
    }
}

/// Ringpuffer für den Ton kurz vor Sprachbeginn – sonst fehlt Whisper der erste Laut.
struct PreRoll {
    let capacity: Int
    private var buf: [Float] = []

    init(seconds: Double, sampleRate: Double = 16_000) { capacity = Int(seconds * sampleRate) }

    mutating func append(_ s: [Float]) {
        buf.append(contentsOf: s)
        if buf.count > capacity { buf.removeFirst(buf.count - capacity) }
    }

    mutating func drain() -> [Float] { defer { buf.removeAll(keepingCapacity: true) }; return buf }
    mutating func clear() { buf.removeAll(keepingCapacity: true) }
    var count: Int { buf.count }
}

/// Umrechnung beliebiger PCM-Puffer auf 16 kHz Mono Float (Whisper-Eingabe).
final class Resampler16k {
    static let rate = 16_000.0
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var source: AVAudioFormat?

    func convert(_ buf: AVAudioPCMBuffer) -> [Float] {
        guard buf.frameLength > 0 else { return [] }
        if converter == nil || source != buf.format {
            converter = AVAudioConverter(from: buf.format, to: target)
            source = buf.format
        }
        guard let converter else { return [] }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * Self.rate / buf.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return [] }
        var given = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return buf
        }
        guard err == nil, let ch = out.floatChannelData, out.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    func reset() { converter?.reset() }
}

/// Modellauswahl: nur Varianten, die WhisperKit für dieses Gerät als unterstützt meldet, keine reinen
/// Englisch-Modelle (`.en`), keine Distil-Modelle (nur Englisch).
enum WhisperCatalog {
    static func choices(supported: [String]) -> [String] {
        supported.filter { !$0.hasSuffix(".en") && !$0.contains(".en_") && !$0.contains("distil") }
    }

    static func defaultModel(recommended: String, supported: [String]) -> String? {
        let c = choices(supported: supported)
        if c.contains(recommended) { return recommended }
        return c.first { $0.contains("base") } ?? c.first
    }

    /// Ungefähre Downloadgröße in MB (Name enthält sie oft, sonst Tabelle).
    static func sizeMB(_ variant: String) -> Int? {
        if let r = variant.range(of: #"_(\d+)MB"#, options: .regularExpression) {
            return Int(variant[r].dropFirst().dropLast(2))
        }
        let table: [(String, Int)] = [("tiny", 76), ("base", 146), ("small", 487), ("medium", 1530),
                                      ("large-v3-v20240930_turbo", 1620), ("large", 3100)]
        return table.first { variant.contains($0.0) }?.1
    }

    /// Kurzer Anzeigename: „openai_whisper-base“ -> „base“.
    static func label(_ variant: String) -> String {
        variant.replacingOccurrences(of: "openai_whisper-", with: "")
    }
}
