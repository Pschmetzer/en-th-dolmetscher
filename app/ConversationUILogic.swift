// ConversationUILogic.swift – reine Logikbausteine der Runde 23 für Hauptfenster, Blasen und Engine-Überwachung
// (nur Foundation; getestet in swift-tests). Treffer-Navigation, Mehrfachauswahl, Zahlenwarnung, Lesarten,
// Latenz-Sparkline, Übersteuerung, Schrift-Abweichung, Tipps, Partial-Drossel, Wachhund, Unterbrochen-Marke.
import Foundation

// MARK: Treffer-Navigation (Suche „2 / 7“, ⌘G)

enum HitNavigator {
    /// Treffer je Blase (Original + Übersetzung zusammen) für die Reihenfolge der gezeigten Blasen.
    static func counts(query: String, texts: [(String, String)]) -> [Int] {
        texts.map { SearchHits.occurrences(of: query, in: $0.0) + SearchHits.occurrences(of: query, in: $0.1) }
    }

    /// Index der Blase, die den globalen Treffer `hit` (0-basiert) enthält.
    static func bubbleIndex(forHit hit: Int, counts: [Int]) -> Int? {
        guard hit >= 0 else { return nil }
        var rest = hit
        for (i, c) in counts.enumerated() {
            if rest < c { return i }
            rest -= c
        }
        return nil
    }

    /// Aktueller Treffer nach Änderung der Trefferzahl: bleibt gültig oder fällt auf nil zurück.
    static func clamp(_ current: Int?, count: Int) -> Int? {
        guard let c = current, c >= 0, c < count else { return nil }
        return c
    }
}

// MARK: Mehrfachauswahl von Blasen

struct BubbleSelection: Equatable {
    private(set) var ids: [String] = []        // Reihenfolge der Auswahl nicht wichtig, Duplikate ausgeschlossen
    private var anchor: String?

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }
    func contains(_ id: String) -> Bool { ids.contains(id) }

    mutating func toggle(_ id: String) {
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
        anchor = id
    }

    /// Umschalt-Klick: alles von der zuletzt angeklickten Blase bis `id` (in Anzeigereihenfolge `order`) auswählen.
    mutating func extend(to id: String, in order: [String]) {
        guard let a = anchor, let i = order.firstIndex(of: a), let j = order.firstIndex(of: id) else { toggle(id); return }
        for k in min(i, j)...max(i, j) where !ids.contains(order[k]) { ids.append(order[k]) }
        anchor = id
    }

    mutating func selectAll(_ order: [String]) { ids = order; anchor = order.last }
    mutating func clear() { ids = []; anchor = nil }

    /// Auswahl auf noch vorhandene Blasen beschränken (Blase gelöscht/Filter geändert).
    mutating func prune(keeping order: [String]) {
        let keep = Set(order)
        ids.removeAll { !keep.contains($0) }
        if let a = anchor, !keep.contains(a) { anchor = nil }
    }

    /// Ausgewählte Blasen in Anzeigereihenfolge.
    func ordered(_ order: [String]) -> [String] {
        let s = Set(ids)
        return order.filter { s.contains($0) }
    }

    /// VoiceOver-/Statuszeile: „3 von 12 ausgewählt“ – Text liefert der Aufrufer, hier nur die Zahlen.
    static func summary(selected: Int, total: Int) -> String { "\(selected) / \(total)" }
}

// MARK: Zahlenwarnung (auffälliger, mit den betroffenen Zahlen)

enum NumberWarning {
    struct Diff: Equatable {
        var missing: [String]   // im Original, aber nicht in der Übersetzung
        var extra: [String]     // in der Übersetzung, aber nicht im Original
        var isEmpty: Bool { missing.isEmpty && extra.isEmpty }
    }

    /// Ziffernfolgen (auch Thai-/arabisch-indische Ziffern werden normalisiert) mit Dezimal-/Tausendertrennern, z. B. „1,200“, „3.5“, „14:30“.
    static func numbers(in text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        func flush() {
            while let l = cur.last, l == "," || l == "." || l == ":" { cur.removeLast() }
            if !cur.isEmpty { out.append(cur) }
            cur = ""
        }
        for ch in text {
            if let d = digit(ch) { cur.append(d) }
            else if (ch == "," || ch == "." || ch == ":"), !cur.isEmpty { cur.append(ch) }
            else { flush() }
        }
        flush()
        return out
    }

    private static func digit(_ ch: Character) -> Character? {
        guard let s = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return nil }
        switch s.value {
        case 0x30...0x39: return ch
        case 0x0E50...0x0E59: return Character(UnicodeScalar(0x30 + (s.value - 0x0E50))!)   // Thai-Ziffern
        case 0x0660...0x0669: return Character(UnicodeScalar(0x30 + (s.value - 0x0660))!)   // arabisch-indisch
        default: return nil
        }
    }

    /// Unterschied der Zahlen (als Vielfachmenge) zwischen Original und Übersetzung.
    static func diff(original: String, translation: String) -> Diff {
        var rest = numbers(in: translation)
        var missing: [String] = []
        for n in numbers(in: original) {
            if let i = rest.firstIndex(of: n) { rest.remove(at: i) } else { missing.append(n) }
        }
        return Diff(missing: missing, extra: rest)
    }

    /// Kurzform für die Anzeige: höchstens `limit` Zahlen, mit „…“ bei mehr.
    static func listed(_ nums: [String], limit: Int = 4) -> String {
        guard nums.count > limit else { return nums.joined(separator: ", ") }
        return nums.prefix(limit).joined(separator: ", ") + " …"
    }
}

// MARK: Andere Lesarten durchblättern

enum AltCycle {
    /// Nächster Index in 0 … count (0 = aktueller Text, 1…count = Lesarten); umlaufend.
    static func next(_ current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (max(0, current) + 1) % (count + 1)
    }

    /// „2 / 4“ – Position unter allen Varianten (Original eingerechnet).
    static func label(index: Int, count: Int) -> String { "\(min(max(0, index), count) + 1) / \(count + 1)" }
}

// MARK: Latenz-Sparkline

enum LatencySpark {
    static let blocks: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    /// Eine Zeile Blockzeichen für die letzten Werte (Sekunden); Skala von 0 bis max(Wert, 4 s), damit kleine Schwankungen klein bleiben.
    static func line(_ values: [Double], limit: Int = 10) -> String {
        let v = values.suffix(limit).filter { $0.isFinite && $0 >= 0 }
        guard !v.isEmpty else { return "" }
        let top = max(4, v.max() ?? 4)
        return String(v.map { x in blocks[min(blocks.count - 1, Int((x / top) * Double(blocks.count - 1) + 0.5))] })
    }

    enum Trend: Equatable { case flat, up, down }

    /// Trend: Mittel der jüngeren Hälfte gegen die ältere (Schwelle 0,5 s); weniger als 4 Werte → flach.
    static func trend(_ values: [Double]) -> Trend {
        let v = values.filter { $0.isFinite }
        guard v.count >= 4 else { return .flat }
        let half = v.count / 2
        let old = v.prefix(half).reduce(0, +) / Double(half)
        let new = v.suffix(half).reduce(0, +) / Double(half)
        if new - old > 0.5 { return .up }
        if old - new > 0.5 { return .down }
        return .flat
    }
}

// MARK: Übersteuerung (Pegel dauerhaft am Anschlag)

/// `level.rms` der Engine ist −60…0 dBFS auf 0…1 abgebildet: ≥ 0,95 entspricht über −3 dBFS.
struct ClippingDetector: Equatable {
    static let threshold = 0.95
    static let needed = 6                  // ≈ 1 s bei 7 Pegelwerten pro Sekunde
    private(set) var run = 0
    private(set) var warned = false

    /// Neuer Pegelwert; true = Warnung ist (jetzt) aktiv.
    @discardableResult
    mutating func feed(_ rms: Double) -> Bool {
        if rms >= Self.threshold { run += 1; if run >= Self.needed { warned = true } }
        else { run = 0; if rms < 0.8 { warned = false } }   // Hysterese: erst deutlich darunter wieder frei
        return warned
    }
    mutating func reset() { run = 0; warned = false }
}

// MARK: Schrift passt nicht zur eingestellten Richtung

enum ScriptMismatch {
    enum Script: Equatable { case thai, latin, other }

    static func dominant(_ text: String) -> Script? {
        var thai = 0, latin = 0
        for u in text.unicodeScalars {
            if (0x0E00...0x0E7F).contains(u.value) { thai += 1 }
            else if CharacterSet.letters.contains(u), u.value < 0x250 { latin += 1 }
        }
        guard thai + latin >= 3 else { return nil }
        return thai >= latin ? .thai : .latin
    }

    static func expected(_ lang: String) -> Script? {
        switch lang {
        case "th": return .thai
        case "en", "de", "fr", "es", "it", "pt", "nl", "sv", "da", "no", "pl", "tr", "id", "ms", "vi": return .latin
        default: return nil
        }
    }

    /// Wahr, wenn die Richtung auf `forced` festgelegt ist, die letzten Äußerungen aber in einer anderen Schrift stehen.
    /// `recent`: Originaltexte, neueste zuletzt. Mindestens `needed` der letzten drei müssen abweichen.
    static func shouldHint(forced: String, recent: [String], needed: Int = 2) -> Bool {
        guard forced != "auto", forced != "", let exp = expected(forced) else { return false }
        let last = recent.suffix(3).compactMap { dominant($0) }
        return last.filter { $0 != exp }.count >= needed
    }
}

// MARK: Tipps im leeren Verlauf

enum EmptyTips {
    static let keys = ["tip_space", "tip_phrase", "tip_partner", "tip_search", "tip_mini", "tip_correct"]
    /// Ein Tipp je Kalendertag, damit er sich nicht bei jedem Neuzeichnen ändert.
    static func key(on date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return keys[((day % keys.count) + keys.count) % keys.count]
    }
}

// MARK: Partial-Drossel (Rückstau)

/// Begrenzt, wie oft Zwischentexte (`partial`) je Äußerung in die Oberfläche geschrieben werden.
/// `now` ist monotone Zeit in Sekunden (ProcessInfo.systemUptime), nie die Wanduhr.
struct PartialThrottle: Equatable {
    static let minInterval: TimeInterval = 0.12
    private var lastApplied: [String: TimeInterval] = [:]
    private var lastText: [String: String] = [:]

    enum Decision: Equatable { case apply, skip, deferFor(TimeInterval) }

    /// apply: jetzt schreiben. skip: unverändert. deferFor: später nachreichen (Rest der Wartezeit).
    mutating func decide(id: String, text: String, now: TimeInterval) -> Decision {
        if lastText[id] == text { return .skip }
        if let t = lastApplied[id], now - t < Self.minInterval, now >= t {
            return .deferFor(Self.minInterval - (now - t))
        }
        lastApplied[id] = now; lastText[id] = text
        return .apply
    }

    /// Nachgereichten Text als geschrieben markieren.
    mutating func markApplied(id: String, text: String, now: TimeInterval) { lastApplied[id] = now; lastText[id] = text }
    mutating func forget(_ id: String) { lastApplied[id] = nil; lastText[id] = nil }
    mutating func reset() { lastApplied = [:]; lastText = [:] }
}

// MARK: Wachhund auf monotoner Uhr

enum MonotonicClock {
    /// Sekunden seit Start; unabhängig von Wanduhr-Sprüngen (Zeitzone, NTP, manuelles Stellen).
    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

enum WatchdogLogic {
    struct State: Equatable {
        var lastAlive: TimeInterval
        var lastTick: TimeInterval
    }
    enum Verdict: Equatable { case ok, hung, restart }

    /// Ein Wachhund-Takt: Ruhezustand/App Nap (großer Abstand zwischen Takten) setzt „lebt“ zurück;
    /// danach Urteil nach Dauer ohne Lebenszeichen.
    static func tick(_ s: inout State, now: TimeInterval, pongSeen: Bool, alreadyHung: Bool, idle: Bool,
                     restartsSoFar: Int, pingEvery: TimeInterval, hungAfter: TimeInterval,
                     hungRestartAfter: TimeInterval, maxRestarts: Int = 3) -> Verdict {
        if now - s.lastTick > pingEvery * 2.5 || now < s.lastTick { s.lastAlive = now }   // Sprung zurück: nie „hängt“
        s.lastTick = now
        let silent = now - s.lastAlive
        if alreadyHung, silent > hungRestartAfter, restartsSoFar < maxRestarts,
           idle || silent > hungRestartAfter * 3 { return .restart }
        if pongSeen, silent > hungAfter { return .hung }
        return alreadyHung ? .hung : .ok
    }
}

// MARK: „unterbrochen“-Marke nach Engine-Absturz

enum InterruptedMark {
    /// Ist von einem Platzhalter etwas Brauchbares übrig (Teiltext), das als Blase erhalten bleibt?
    static func keepText(partial: String?) -> String? {
        let t = (partial ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: Exportoptionen (Sprache, Uhrzeiten) für die Auswahl/Treffer

enum ExportSelection {
    /// Zeilen behalten, die `options` erlaubt (nur eine Sprache).
    static func filter<T>(_ items: [T], options: ExportOptions, lang: (T) -> String) -> [T] {
        items.filter { options.keep(lang: lang($0)) }
    }

    /// Uhrzeit-Präfix „[14:32] “ nur, wenn `options.includeTimes`.
    static func stamp(_ date: Date, options: ExportOptions, calendar: Calendar = .current) -> String {
        options.includeTimes ? "[" + A11yBubble.clock(date, calendar: calendar) + "] " : ""
    }
}

// MARK: Partner-Ansicht: Thai größer

enum PartnerScript {
    /// Thai hat keine Großbuchstaben und viele Ober-/Unterzeichen: bei gleicher Punktgröße wirkt es kleiner.
    static func boost(lang: String) -> Double { lang == "th" ? 1.18 : 1.0 }
}
