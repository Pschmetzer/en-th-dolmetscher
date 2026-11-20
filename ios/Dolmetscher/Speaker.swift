// Speaker.swift – Sprachausgabe mit den Systemstimmen. `speak` kehrt zurück, wenn der Satz zu Ende ist.
import AVFoundation

@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var cont: CheckedContinuation<Void, Never>?
    private var token = 0
    private var current: AVSpeechUtterance?
    private var guardTask: Task<Void, Never>?
    /// Gewählte Stimme je Sprache (638): `speechVoices()` ist teuer. Leeren, wenn Stimmen dazukommen.
    private static var voiceCache: [Lang: AVSpeechSynthesisVoice] = [:]

    override init() {
        super.init()
        synth.delegate = self
        NotificationCenter.default.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in Speaker.voiceCache = [:]; Speaker.hasVoiceCache = [:] }
        }
    }

    static func voice(_ lang: Lang) -> AVSpeechSynthesisVoice? {
        if let v = voiceCache[lang] { return v }
        let v = findVoice(lang)
        if let v { voiceCache[lang] = v }
        return v
    }

    private static func findVoice(_ lang: Lang) -> AVSpeechSynthesisVoice? {
        let code = lang.rawValue
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == code || $0.language.hasPrefix(code + "-") }
        let preferred = lang.voiceLocale
        // Erst die Region der Sprache (zh-CN statt zh-HK), dann die Qualität.
        return all.max { a, b in
            (a.language == preferred ? 1 : 0, a.quality.rawValue) < (b.language == preferred ? 1 : 0, b.quality.rawValue)
        } ?? AVSpeechSynthesisVoice(language: preferred)
    }

    /// Gibt es auf dem Gerät überhaupt eine Stimme für die Sprache?
    static func hasVoice(_ lang: Lang) -> Bool {
        if let v = hasVoiceCache[lang] { return v }
        let code = lang.rawValue
        let v = AVSpeechSynthesisVoice.speechVoices().contains { $0.language == code || $0.language.hasPrefix(code + "-") }
        hasVoiceCache[lang] = v
        return v
    }
    /// `speechVoices()` ist teuer; die Ansichten fragen bei jedem Aktualisieren. Wie `voiceCache` bei neuen Stimmen leeren.
    private static var hasVoiceCache: [Lang: Bool] = [:]

    /// `rate`: 1 = normal (0.5 … 1.5), `volume`: 0 … 1. `clear`: „Langsam und deutlich“ – Pausen zwischen Satzteilen.
    func speak(_ text: String, lang: Lang, rate: Double, volume: Double, clear: Bool = false) async {
        finish()
        let spoken = SpeechText.normalize(text, lang: lang)
        let ssml = clear ? ClearSpeech.ssml(spoken, lang: lang) : nil
        let u = ssml.flatMap { AVSpeechUtterance(ssmlRepresentation: $0) } ?? AVSpeechUtterance(string: spoken)
        u.voice = Self.voice(lang)
        let d = AVSpeechUtteranceDefaultSpeechRate
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, d * Float(rate)))
        u.volume = Float(min(1, max(0.05, volume)))
        token += 1
        let mine = token
        // Sicherung, falls das System nie „fertig“ meldet (z. B. Stimme fehlt). Langsam und mit Pausen dauert länger.
        let limit = ClearSpeech.timeout(chars: spoken.count, rate: rate, pauses: ssml == nil ? 0 : ClearSpeech.pauseCount(spoken, lang: lang))
        guardTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled else { return }
            if let self, self.token == mine { self.synth.stopSpeaking(at: .immediate); self.finish() }
        }
        await withCheckedContinuation { c in
            cont = c
            current = u
            synth.speak(u)
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        finish()
    }

    /// Rückruf des Systems: nur der gerade laufende Satz zählt (ein verspätetes „abgebrochen“ des vorigen nicht).
    private func ended(_ u: AVSpeechUtterance) {
        if u === current { finish() }
    }

    private func finish() {
        guardTask?.cancel()   // 637: Sicherung nicht weiter schlafen lassen
        guardTask = nil
        token += 1
        current = nil
        cont?.resume()
        cont = nil
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.ended(u) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.ended(u) }
    }
}

/// „Langsam und deutlich“ (906): Satzteile mit kurzen Pausen (SSML), für Lernende und schlechtes Hören.
enum ClearSpeech {
    static let pause = 0.35

    /// Satzteile: an Satzzeichen; Thai hat keine Wortabstände, dort trennt das Leerzeichen Satzteile.
    static func chunks(_ text: String, lang: Lang) -> [String] {
        let marks: Set<Character> = [",", ".", ";", ":", "!", "?", "、", "。", "，", "！", "？"]
        var out: [String] = [], cur = ""
        for ch in text {
            let splitHere = marks.contains(ch) || (lang == .th && ch == " ")
            if splitHere {
                if ch != " " { cur.append(ch) }
                let t = cur.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { out.append(t) }
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        let t = cur.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { out.append(t) }
        return out
    }

    static func pauseCount(_ text: String, lang: Lang) -> Int { max(0, chunks(text, lang: lang).count - 1) }

    /// SSML mit Pausen; nil, wenn es nichts zu trennen gibt (dann reicht normaler Text).
    static func ssml(_ text: String, lang: Lang) -> String? {
        let parts = chunks(text, lang: lang)
        guard parts.count > 1 else { return nil }
        let ms = Int(pause * 1000)
        return "<speak>" + parts.map(escape).joined(separator: "<break time=\"\(ms)ms\"/>") + "</speak>"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Sicherungs-Zeitlimit: 8 s + 0,25 s je Zeichen, langsamer gesprochen entsprechend länger, plus Pausen.
    static func timeout(chars: Int, rate: Double, pauses: Int) -> Double {
        (8 + Double(chars) * 0.25) / max(0.3, min(1, rate)) + Double(pauses) * pause
    }
}

/// Text für die Stimme aufbereiten (600): Währungszeichen und Eigennamen, die Thai-Stimmen sonst verschlucken.
enum SpeechText {
    static func normalize(_ text: String, lang: Lang) -> String {
        var s = text
        if lang == .th {
            for (a, b) in [("7-Eleven", "เซเว่นอีเลฟเว่น"), ("7-11", "เซเว่นอีเลฟเว่น"), ("Wi-Fi", "ไวไฟ"), ("WiFi", "ไวไฟ"), ("BTS", "บีทีเอส"), ("MRT", "เอ็มอาร์ที")] {
                s = s.replacingOccurrences(of: a, with: b, options: .caseInsensitive)
            }
            s = currency(s, word: "บาท")
        } else {
            s = currency(s, word: lang == .en ? "baht" : "Baht")
        }
        return s
    }

    /// „฿120“ oder „120฿“ -> „120 baht“; ein einzelnes ฿ ohne Zahl -> das Wort.
    private static func currency(_ s: String, word: String) -> String {
        guard s.contains("฿") else { return s }
        var out = s
        if let re = try? NSRegularExpression(pattern: "฿\\s*([0-9][0-9,.]*)") {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1 " + word)
        }
        if let re = try? NSRegularExpression(pattern: "([0-9])\\s*฿") {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1 " + word)
        }
        return out.replacingOccurrences(of: "฿", with: word)
    }
}
