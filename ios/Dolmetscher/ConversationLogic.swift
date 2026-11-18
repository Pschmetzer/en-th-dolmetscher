// ConversationLogic.swift – reine Logik des Gesprächsmodus (Runde 15): Schriftgröße je Hälfte, Zustandsanzeige,
// Echo-Erkennung (eigene Ausgabe nicht erneut erkennen), Stille, Zahl-Hervorhebung, Layout. Ohne UI, testbar.
import Foundation

enum ConversationLogic {
    // MARK: Schriftgröße je Hälfte

    static let fontScales: [Double] = [0.85, 1.0, 1.25, 1.5, 1.8]
    static let defaultFontStep = 1

    static func clampStep(_ s: Int) -> Int { min(max(s, 0), fontScales.count - 1) }
    static func scale(step: Int) -> Double { fontScales[clampStep(step)] }
    static func stepped(_ s: Int, by d: Int) -> Int { clampStep(s + d) }

    // MARK: Zustand (Text und Symbol, nie nur Farbe)

    enum SideState: Equatable { case idle, listening, translating, speaking }

    static func state(expecting: Bool, listening: Bool, hearing: Bool, translating: Bool, speaking: Bool) -> SideState {
        if speaking { return .speaking }
        if translating { return .translating }
        if expecting && listening { return hearing ? .listening : .idle }
        return .idle
    }

    static func textKey(_ s: SideState) -> String {
        switch s {
        case .idle: return "conv_state_idle"
        case .listening: return "conv_state_listening"
        case .translating: return "conv_state_translating"
        case .speaking: return "conv_state_speaking"
        }
    }

    static func icon(_ s: SideState) -> String {
        switch s {
        case .idle: return "pause.circle"
        case .listening: return "ear"
        case .translating: return "arrow.triangle.2.circlepath"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    // MARK: Echo und Stille

    /// Der Zuhörknopf ist gesperrt, solange das Gerät selbst spricht (sonst hört es sich zu).
    static func turnLocked(speaking: Bool) -> Bool { speaking }

    private static func normalized(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Ist `heard` (fast) dasselbe wie eine der zuletzt selbst gesprochenen Ausgaben?
    static func isEcho(_ heard: String, spoken: [String]) -> Bool {
        let h = normalized(heard)
        guard h.count >= 3 else { return false }
        for s in spoken {
            let n = normalized(s)
            guard !n.isEmpty else { continue }
            if n == h { return true }
            let (short, long) = h.count <= n.count ? (h, n) : (n, h)
            if short.count >= 6, long.contains(short), Double(short.count) / Double(long.count) >= 0.5 { return true }
            if bigramOverlap(h, n) >= 0.8 { return true }
        }
        return false
    }

    private static func bigramOverlap(_ a: String, _ b: String) -> Double {
        func grams(_ s: String) -> Set<String> {
            let c = Array(s)
            guard c.count >= 2 else { return [] }
            return Set((0..<(c.count - 1)).map { String(c[$0...$0 + 1]) })
        }
        let x = grams(a), y = grams(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(x.union(y).count)
    }

    /// Ausgaben der letzten `window` Sekunden, gegen die geprüft wird.
    static let echoWindow: TimeInterval = 10

    static func recent(_ spoken: [(text: String, at: Date)], now: Date) -> [String] {
        spoken.filter { now.timeIntervalSince($0.at) <= echoWindow }.map(\.text)
    }

    /// Stille: seit `silenceSeconds` kein Sprechen mehr erkannt.
    static let silenceSeconds: TimeInterval = 4
    static func isSilent(lastSpeech: Date, now: Date) -> Bool { now.timeIntervalSince(lastSpeech) >= silenceSeconds }

    // MARK: Wiederholen / Langsam

    /// Letzter Eintrag, der in dieser Sprache angezeigt wird und eine Übersetzung hat (zum Wiederholen).
    static func lastSpeakable(_ entries: [Entry], lang: Lang) -> Entry? {
        entries.last { $0.target == lang && !($0.translation ?? "").isEmpty }
    }

    // MARK: Zahlen hervorheben

    /// Zahlengruppen (auch Tausender-/Dezimaltrenner und Ziffern anderer Schriften) im Text.
    static func numberRanges(in text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        var i = text.startIndex
        func isDigit(_ c: Character) -> Bool { c.isNumber && c.wholeNumberValue != nil }
        while i < text.endIndex {
            let c = text[i]
            let next = text.index(after: i)
            if isDigit(c) {
                if start == nil { start = i }
            } else if let s = start {
                let joins = (c == "." || c == "," || c == ":" ) && next < text.endIndex && isDigit(text[next])
                if !joins { out.append(s..<i); start = nil }
            }
            i = next
        }
        if let s = start { out.append(s..<text.endIndex) }
        return out
    }

    static func highlighted(_ text: String) -> AttributedString {
        var a = AttributedString(text)
        for r in numberRanges(in: text) {
            if let lo = AttributedString.Index(r.lowerBound, within: a), let hi = AttributedString.Index(r.upperBound, within: a) {
                a[lo..<hi].inlinePresentationIntent = .stronglyEmphasized
                a[lo..<hi].underlineStyle = .single
            }
        }
        return a
    }

    // MARK: Layout

    /// Nebeneinander statt untereinander: Querformat oder breite Fläche (iPad).
    static func sideBySide(width: Double, height: Double) -> Bool { width > height && width >= 600 }
}
