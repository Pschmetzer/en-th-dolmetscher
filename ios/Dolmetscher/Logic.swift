// Logic.swift – reine Logik ohne Geräte-APIs: Sprachen, Sprachbefehle, Sprachwahl. Unit-getestet.
import Foundation

enum Lang: String, Codable, CaseIterable, Sendable {
    case en, th
    var other: Lang { self == .en ? .th : .en }
}

/// Ein Erkennungsergebnis einer Sprache für eine Äußerung.
struct Hypothesis: Equatable, Sendable {
    var text: String
    var confidence: Double
}

enum VoiceCommand: String, CaseIterable, Sendable {
    case wake, pause, resume, `repeat`, slower, faster, louder, quieter, clear, help
}

/// Weckwort „Translator“ und Befehle – gleiche Regeln wie die Mac-Engine (dolmetscher.py).
enum Commands {
    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }
    private static let wake = rx(#"^\W*(?:hey|hi|ok|okay)?\W*translat(?:or|er)\b\W*(.*)$"#)
    /// unscharf („Translate or pause“) – zählt nur, wenn ein Befehl folgt
    private static let wakeFuzzy = rx(#"^\W*(?:hey|hi|ok|okay)?\W*tr\w*nsl\w*\W*(?:(?:or|to|a|the|uh|um)\b\W*)*(.*)$"#)

    /// Schlüsselwörter je Befehl (inkl. typischer Verhörer)
    static let table: [(VoiceCommand, [String])] = [
        (.pause, ["pause", "stop", "sleep", "be quiet", "mute", "post", "pulse", "pose", "paws",
                  "pours", "pals", "pass", "porsche", "paul's", "pores"]),
        (.resume, ["resume", "continue", "start", "wake up", "go on", "unpause", "presume", "rezoom"]),
        (.repeat, ["repeat", "again", "say that", "re-peat", "repeats"]),
        (.slower, ["slower", "slow down", "slowly"]),
        (.faster, ["faster", "speed up", "quicker"]),
        (.louder, ["louder", "volume up", "lauder"]),
        (.quieter, ["quieter", "softer", "volume down", "quiet"]),
        (.clear, ["clear", "delete", "reset", "clean"]),
        (.help, ["help", "commands", "what can you do"]),
    ]

    private static func rest(_ r: NSRegularExpression, _ s: String) -> String? {
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Befehlstext (ohne Weckwort) -> Befehl. Leerer Text = nur das Weckwort.
    static func parse(_ cmd: String) -> VoiceCommand? {
        let c = cmd.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,!?\n"))
        if c.isEmpty { return .wake }
        for (key, words) in table {
            for w in words {
                let p = "\\b" + NSRegularExpression.escapedPattern(for: w) + "\\b"
                if c.range(of: p, options: .regularExpression) != nil { return key }
            }
        }
        return nil
    }

    /// Ganzer englischer Satz -> Befehl oder nil (dann normal übersetzen).
    /// `awake`: kurz zuvor fiel nur das Weckwort, der nächste Satz darf der Befehl ohne Weckwort sein.
    static func detect(_ text: String, awake: Bool = false) -> VoiceCommand? {
        if let r = rest(wake, text) { return parse(r) }
        // Unscharf („Translate or pause“) nur, wenn danach kaum mehr kommt als der Befehl –
        // sonst wäre „Translate: please stop here“ ein Befehl statt eines Satzes.
        if let r = rest(wakeFuzzy, text), r.split(whereSeparator: { $0.isWhitespace }).count <= 3,
           let k = parse(r), k != .wake { return k }
        if awake, let k = parse(text), k != .wake { return k }
        return nil
    }
}

enum LanguagePick {
    /// Anteil thailändischer Schriftzeichen an allen Buchstaben.
    static func thaiShare(_ s: String) -> Double {
        var thai = 0, letters = 0
        for u in s.unicodeScalars where u.properties.isAlphabetic {
            letters += 1
            if (0x0E00...0x0E7F).contains(u.value) { thai += 1 }
        }
        return letters == 0 ? 0 : Double(thai) / Double(letters)
    }

    /// Sprache eines getippten Textes.
    static func ofTyped(_ s: String) -> Lang { thaiShare(s) > 0.3 ? .th : .en }

    /// Beide Erkenner haben dieselbe Äußerung gehört – welcher hat recht?
    /// Konfidenzen sind zwischen Sprachen nur grob vergleichbar, deshalb zuerst harte Hinweise.
    /// `bias` > 0 bevorzugt Thai, < 0 Englisch.
    static func pick(en: Hypothesis?, th: Hypothesis?, bias: Double = 0) -> Lang? {
        let e = en.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let t = th.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if e.isEmpty && t.isEmpty { return nil }
        if t.isEmpty { return .en }
        if e.isEmpty { return .th }
        if Commands.detect(e) != nil { return .en }
        // Der Thai-Erkenner schreibt englische Wörter oft lateinisch: dann war es Englisch.
        if thaiShare(t) < 0.5 { return .en }
        return (th?.confidence ?? 0) + bias > (en?.confidence ?? 0) ? .th : .en
    }
}

/// Höflichkeitsform im Thai: Männer enden mit ครับ, Frauen mit ค่ะ (Frage: คะ). Übersetzer wählen oft willkürlich.
enum Politeness: String, CaseIterable, Codable, Sendable {
    case male, female, off

    /// Satzende-Wort für Aussagen bzw. Fragen.
    var statement: String { self == .male ? "ครับ" : self == .female ? "ค่ะ" : "" }
    var question: String { self == .male ? "ครับ" : self == .female ? "คะ" : "" }
    /// „ich“
    var pronoun: String { self == .male ? "ผม" : "ฉัน" }

    /// Höflichkeitswörter am Satzende an die gewählte Form anpassen. `.off` lässt den Text unverändert.
    func adjust(_ thai: String) -> String {
        guard self != .off else { return thai }
        let particles = ["ครับ", "ค่ะ", "คะ", "ค๊ะ", "คับ"]
        var out = ""
        var rest = Substring(thai)
        while !rest.isEmpty {
            if let p = particles.first(where: { rest.hasPrefix($0) }) {
                let after = rest.dropFirst(p.count)
                // Nur am Wort-/Satzende ersetzen (danach Ende, Leerzeichen oder Satzzeichen).
                let next = after.first
                let atEnd = next == nil || next!.isWhitespace || "?!.,।".contains(next!)
                if atEnd {
                    let isQuestion = next == "?" || p == "คะ" || p == "ค๊ะ"
                    out += isQuestion ? question : statement
                    rest = after
                    continue
                }
            }
            out.append(rest.removeFirst())
        }
        return ensureEnding(out)
    }

    /// Fehlt am Ende ein Höflichkeitswort, eins anhängen (vor ? ! .). So klingt jede Übersetzung höflich.
    func ensureEnding(_ thai: String) -> String {
        guard self != .off else { return thai }
        var body = thai.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LanguagePick.thaiShare(body) > 0.5 else { return thai }
        var tail = ""
        while let last = body.last, "?!.".contains(last) { tail = String(last) + tail; body.removeLast() }
        body = body.trimmingCharacters(in: .whitespaces)
        let particles = ["ครับ", "ค่ะ", "คะ", "ค๊ะ", "คับ", "นะ", "จ้ะ", "จ้า", "ครับผม"]
        if particles.contains(where: { body.hasSuffix($0) }) { return thai }
        let isQuestion = tail.contains("?") || ["ไหม", "หรือ", "ไหน", "อะไร", "เท่าไหร่", "เท่าไร", "กี่", "ใคร", "ทำไม", "อย่างไร", "ยังไง", "เมื่อไร", "เมื่อไหร่"].contains { body.hasSuffix($0) }
        return body + (isQuestion ? question : statement) + tail
    }

    /// Platzhalter in Satzbuch-Texten: {p} Aussage-Ende, {q} Frage-Ende, {i} „ich“.
    func fill(_ template: String) -> String {
        template.replacingOccurrences(of: "{p}", with: statement)
            .replacingOccurrences(of: "{q}", with: question)
            .replacingOccurrences(of: "{i}", with: pronoun)
    }

    /// Umschrift der Platzhalter.
    func fillRoman(_ template: String) -> String {
        let p = self == .male ? " khrap" : self == .female ? " kha" : ""
        let q = self == .male ? " khrap" : self == .female ? " kha" : ""
        let i = self == .male ? "phom " : "chan "
        return template.replacingOccurrences(of: " {p}", with: p).replacingOccurrences(of: "{p}", with: p)
            .replacingOccurrences(of: " {q}", with: q).replacingOccurrences(of: "{q}", with: q)
            .replacingOccurrences(of: "{i} ", with: i).replacingOccurrences(of: "{i}", with: i)
    }
}

/// Sprachpausen-Erkennung über die Lautstärke. Das Grundrauschen ist das Minimum der letzten Sekunden –
/// so passt es sich auch an dauerhaften Lärm an (Straße, Tuk-Tuk), in dem es nie ganz still wird.
struct VoiceGate {
    enum Event: Equatable { case started, ended }

    var pause: Double
    var maxUtterance = 25.0
    var minSpeech = 0.12
    var window = 6.0
    var factor: Float = 2.8
    var minThreshold: Float = 0.008

    private(set) var inUtterance = false
    private(set) var noise: Float = 0.004
    private var history: [(rms: Float, dur: Double)] = []
    private var historyDur = 0.0
    private var speechRun = 0.0, silenceRun = 0.0, uttDur = 0.0

    init(pause: Double) { self.pause = pause }

    var threshold: Float { max(minThreshold, noise * factor) }

    mutating func reset() {
        inUtterance = false; speechRun = 0; silenceRun = 0; uttDur = 0
    }

    mutating func step(rms: Float, dur: Double) -> Event? {
        history.append((rms, dur)); historyDur += dur
        while historyDur > window, history.count > 1 { historyDur -= history.removeFirst().dur }
        // 10.-Perzentil statt hartem Minimum: einzelne Aussetzer (digitale Stille) sollen den Pegel nicht nullen.
        let sorted = history.map(\.rms).sorted()
        noise = max(0.0005, sorted[min(sorted.count - 1, sorted.count / 10)])

        var event: Event?
        if rms > threshold {
            speechRun += dur; silenceRun = 0
            if !inUtterance && speechRun >= minSpeech { inUtterance = true; uttDur = 0; event = .started }
        } else {
            silenceRun += dur; speechRun = 0
        }
        if inUtterance {
            uttDur += dur
            if silenceRun >= pause || uttDur > maxUtterance { reset(); event = .ended }
        }
        return event
    }
}
