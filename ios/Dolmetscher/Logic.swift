// Logic.swift – reine Logik ohne Geräte-APIs: Sprachen, Sprachbefehle, Sprachwahl. Unit-getestet.
import Foundation

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
    static func thaiShare(_ s: String) -> Double { Lang.th.scriptShare(s) }

    /// Sprache eines getippten Textes: die Sprache des Paars, deren Schrift den größten Anteil hat.
    /// Bei gleicher Schrift (en/de) entscheidet die eingestellte Richtung (`fallback`).
    static func ofTyped(_ s: String, pair: LangPair = .standard, fallback: Lang? = nil) -> Lang {
        let base = fallback ?? pair.mine
        guard pair.distinguishable else { return base }
        let m = pair.mine.scriptShare(s), p = pair.partner.scriptShare(s)
        if m == 0 && p == 0 { return base }
        // Wie früher bei en/th: schon ein Drittel nicht-lateinischer Schrift zählt (lateinische Namen
        // und Marken stehen oft mitten im Thai-Satz).
        let nonLatin = pair.langs.filter { !$0.scripts.contains(.latin) && $0.scriptShare(s) > 0.3 }
        if nonLatin.count == 1 { return nonLatin[0] }
        return p > m ? pair.partner : pair.mine
    }

    /// Alle Erkenner haben dieselbe Äußerung gehört – welcher hat recht?
    /// Konfidenzen sind zwischen Sprachen nur grob vergleichbar, deshalb zuerst harte Hinweise:
    /// das Weckwort (nur mit Englisch im Paar) und die Schrift (ein Thai-Erkenner, der lateinisch
    /// schreibt, hat Englisch gehört).
    ///
    /// `expect`: „Jetzt Sie“ wurde getippt – diese Sprache gewinnt, sofern die Schrift nicht klar dagegen spricht.
    /// `bias`: weicher Hinweis aus dem Gesprächsverlauf (nach einem Satz in A kommt meist B) – zählt nur bei
    /// knapper Konfidenz.
    static func pick(_ hyps: [Lang: Hypothesis], pair: LangPair, commands: Bool? = nil,
                     bias: Lang? = nil, expect: Lang? = nil) -> Lang? {
        let texts = hyps.compactMapValues { h -> String? in
            let t = h.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let order = pair.langs.filter { texts[$0] != nil } + texts.keys.filter { !pair.contains($0) }.sorted { $0.rawValue < $1.rawValue }
        guard let first = order.first else { return nil }
        if order.count == 1 { return first }
        if commands ?? pair.features.voiceCommands, let e = texts[.en], Commands.detect(e) != nil { return .en }
        var cands = order
        if pair.distinguishable {
            let ok = cands.filter { $0.scriptShare(texts[$0]!) >= 0.5 }
            if ok.count == 1 { return ok[0] }
            if !ok.isEmpty { cands = ok }
        }
        if let expect, cands.contains(expect) { return expect }
        // Konfidenz (+ Bonus für die erwartete Sprache); bei Gleichstand die höhere Schrift-Treue, dann die Reihenfolge im Paar.
        func conf(_ l: Lang) -> Double { (hyps[l]?.confidence ?? 0) + (l == bias ? biasBonus : 0) }
        return cands.max { a, b in
            let ca = conf(a), cb = conf(b)
            if ca != cb { return ca < cb }
            let sa = a.scriptShare(texts[a]!), sb = b.scriptShare(texts[b]!)
            if sa != sb { return sa < sb }
            return (order.firstIndex(of: a) ?? 0) > (order.firstIndex(of: b) ?? 0)
        }
    }

    /// So viel Konfidenz ist der Gesprächs-Hinweis wert: entscheidet nur knappe Fälle.
    static let biasBonus = 0.08

    /// Wer spricht als Nächstes vermutlich? Die andere Sprache des letzten Satzes (Gespräch wechselt ab).
    static func turnBias(lastSpoken: Lang?, pair: LangPair) -> Lang? {
        guard let l = lastSpoken, pair.contains(l) else { return nil }
        return pair.other(l)
    }

    /// Alte Form (en/th) – für Tests und als Regressionsschutz.
    static func pick(en: Hypothesis?, th: Hypothesis?) -> Lang? {
        var h: [Lang: Hypothesis] = [:]
        h[.en] = en
        h[.th] = th
        return pick(h, pair: .standard)
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
