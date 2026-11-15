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
        if let r = rest(wakeFuzzy, text), let k = parse(r), k != .wake { return k }
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
