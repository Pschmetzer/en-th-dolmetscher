// R23SetLogic.swift – Runde 23: reine Logik für Einstellungen, Verlauf, Einrichtung und Menü (nur Foundation,
// per XCTest in swift-tests getestet). Oberfläche: R23SetViews.swift, Texte: L10n+R23b.swift.
import Foundation

// MARK: - Einstellungen

enum R23Settings {
    /// Bleiben beim Zurücksetzen eines Reiters, wie sie sind: Oberflächensprache (sonst plötzlich alles in einer anderen
    /// Sprache), Sprachpaar und Modellgröße (ein anderes Modell kann einen Download von mehreren GB auslösen).
    static let resetKeeps: Set<String> = ["uiLang", "mineLang", "partnerLang", "model"]

    /// Werte, mit denen ein Reiter auf Standard zurückgesetzt wird. Bei laufender sensibler Sitzung bleibt auch
    /// der private Modus unangetastet.
    static func resetValues(group: SettingGroup, sensitiveActive: Bool = false) -> [String: SettingValue] {
        var out: [String: SettingValue] = [:]
        for sp in SettingsLogic.specs where sp.group == group && !resetKeeps.contains(sp.key) {
            if sensitiveActive && sp.key == "privateMode" { continue }
            out[sp.key] = sp.fallback
        }
        return out
    }

    /// Schlüssel eines Reiters, deren Wert vom Standard abweicht (steuert, ob „Zurücksetzen“ aktiv ist).
    static func changedKeys(group: SettingGroup, current: [String: SettingValue]) -> [String] {
        resetValues(group: group).filter { current[$0.key] != nil && current[$0.key] != $0.value }.map { $0.key }.sorted()
    }

    /// Sieht der Text wie ein Zugangsschlüssel aus? (sk-…, Bearer …, lange Zeichenfolge ohne Leerzeichen)
    static func secretLike(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("sk-") || t.lowercased().hasPrefix("bearer ") { return true }
        if t.count >= 32, !t.contains(" "), t.range(of: "^[A-Za-z0-9_\\-]+$", options: .regularExpression) != nil {
            let hasDigit = t.contains { $0.isNumber }, hasLetter = t.contains { $0.isLetter }
            return hasDigit && hasLetter
        }
        return false
    }

    static func display(_ v: SettingValue) -> String {
        switch v {
        case .bool(let b): return b ? "true" : "false"
        case .number(let d): return d == d.rounded() && abs(d) < 1e9 ? String(Int(d)) : String(format: "%g", d)
        case .text(let t): return secretLike(t) ? "•••" : t
        }
    }

    /// Zeilen „Schlüssel = Wert“ der Datei in der Reihenfolge der Reiter; Profil nur als Zeilenzahl, Schlüssel nie.
    static func previewLines(values: [String: SettingValue], profile: SettingsProfile) -> [String] {
        var out: [String] = []
        for sp in SettingsLogic.specs {
            out.append(sp.key + " = " + display(values[sp.key] ?? sp.fallback))
        }
        if let p = profile.quickPhrases { out.append("profile.quickPhrases = \(SettingsLogic.lineCount(p))") }
        if let g = profile.glossary { out.append("profile.glossary = \(SettingsLogic.lineCount(g))") }
        return out
    }

    /// Enthält die fertige Datei etwas, das nach Schlüssel aussieht? Dann darf sie nicht angeboten werden.
    static func containsSecret(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return false }
        func walk(_ o: Any) -> Bool {
            if let s = o as? String { return secretLike(s) }
            if let d = o as? [String: Any] { return d.contains { walk($0.value) } }
            if let a = o as? [Any] { return a.contains { walk($0) } }
            return false
        }
        // Profiltexte (Glossar, Schnellsätze) sind Freitext und werden nicht als Schlüssel gewertet.
        guard var root = obj as? [String: Any] else { return false }
        root["profile"] = nil
        return walk(root)
    }

    /// Ohne Akzente, Groß-/Kleinschreibung und Sonderzeichen (für die Suche).
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }

    /// Suche: jedes Wort der Anfrage muss in Beschriftung oder Hilfetext vorkommen; Wortanfang und Beschriftung
    /// zählen höher. Ergebnis: Schlüssel, beste zuerst (Gleichstand: Reihenfolge der Eingabe).
    static func rank(query: String, entries: [(key: String, label: String, help: String)], limit: Int = 8) -> [String] {
        let words = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        var scored: [(Int, Int, String)] = []
        for (i, e) in entries.enumerated() {
            let label = fold(e.label), help = fold(e.help), key = fold(e.key)
            var score = 0, ok = true
            for w in words {
                if label.hasPrefix(w) { score += 6 }
                else if label.split(separator: " ").contains(where: { $0.hasPrefix(w) }) { score += 4 }
                else if label.contains(w) { score += 3 }
                else if key.contains(w) { score += 2 }
                else if help.contains(w) { score += 1 }
                else { ok = false; break }
            }
            if ok { scored.append((score, i, e.key)) }
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
        return scored.prefix(limit).map { $0.2 }
    }
}

// MARK: - Verlauf: Filter nach Sprecher, Sprache, Datum

enum R23DatePreset: String, CaseIterable, Equatable {
    case all, today, week, month
    func interval(now: Date, calendar: Calendar) -> (from: Date?, to: Date?) {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .all: return (nil, nil)
        case .today: return (startOfToday, nil)
        case .week: return (calendar.date(byAdding: .day, value: -6, to: startOfToday), nil)
        case .month: return (calendar.date(byAdding: .day, value: -29, to: startOfToday), nil)
        }
    }
}

struct R23HistoryFacet: Equatable {
    var speaker = ""                    // "" = alle; sonst Wert aus `speakerKey`
    var lang = ""                       // "" = alle (zusätzlich zum Sprachfilter von HistoryFilter)
    var datePreset: R23DatePreset = .all
    var customFrom: Date?
    var customTo: Date?
    var isActive: Bool { !speaker.isEmpty || !lang.isEmpty || datePreset != .all || customFrom != nil || customTo != nil }
}

enum R23History {
    /// Sprecher einer Zeile: Name der Engine, sonst „me“/„other“, sonst leer.
    static func speakerKey(_ r: HistoryRow) -> String {
        if let s = r.speaker, !s.isEmpty { return s }
        return r.role ?? ""
    }

    static func speakers(in sessions: [HistorySession]) -> [String] {
        Array(Set(sessions.flatMap { $0.rows.map(speakerKey) }.filter { !$0.isEmpty })).sorted()
    }

    static func languages(in sessions: [HistorySession]) -> [String] {
        Array(Set(sessions.flatMap { $0.rows.map { $0.lang } }.filter { !$0.isEmpty })).sorted()
    }

    static func matches(_ r: HistoryRow, _ f: R23HistoryFacet, now: Date, calendar: Calendar) -> Bool {
        if !f.speaker.isEmpty, speakerKey(r) != f.speaker { return false }
        if !f.lang.isEmpty, r.lang != f.lang { return false }
        var (from, to) = f.datePreset.interval(now: now, calendar: calendar)
        if let c = f.customFrom { from = calendar.startOfDay(for: c) }
        if let c = f.customTo { to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: c)) }
        if let from, r.time < from { return false }
        if let to, r.time >= to { return false }
        return true
    }

    /// Nur die passenden Zeilen; Sitzungen ohne Treffer fallen weg.
    static func apply(_ sessions: [HistorySession], facet f: R23HistoryFacet, now: Date = Date(),
                      calendar: Calendar = .current) -> [HistorySession] {
        guard f.isActive else { return sessions }
        return sessions.compactMap { s in
            let rows = s.rows.filter { matches($0, f, now: now, calendar: calendar) }
            return rows.isEmpty ? nil : HistorySession(id: s.id, start: s.start, rows: rows)
        }
    }

    // MARK: Mehrfachauswahl

    /// Auswahl umschalten (⌘-Klick).
    static func toggled(_ sel: Set<String>, _ id: String) -> Set<String> {
        var s = sel
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        return s
    }

    /// Bereich zwischen Anker und Ziel in der angezeigten Reihenfolge (Umschalt-Klick); unbekannter Anker: nur das Ziel.
    static func range(_ order: [String], anchor: String?, to id: String) -> Set<String> {
        guard let a = anchor, let i = order.firstIndex(of: a), let j = order.firstIndex(of: id) else { return [id] }
        return Set(order[min(i, j)...max(i, j)])
    }

    /// Ausgewählte Sitzungen in der Reihenfolge der Anzeige, unbekannte Kennungen fallen weg.
    static func selected(_ sessions: [HistorySession], ids: Set<String>) -> [HistorySession] {
        sessions.filter { ids.contains($0.id) }
    }

    /// Alle Zeilen der Auswahl in zeitlicher Reihenfolge (Grundlage für gemeinsamen Export).
    static func mergedRows(_ sessions: [HistorySession]) -> [HistoryRow] {
        sessions.flatMap { $0.rows }.sorted { $0.time < $1.time }
    }

    // MARK: Anki

    /// Feld in Anführungszeichen; Zeilenumbrüche werden `<br>` (Anki liest HTML), keine Formel-Maskierung nötig.
    static func ankiField(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br>")
        return "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Anki-Import als CSV: Vorderseite = Satz in der Fremdsprache, Rückseite = Übersetzung (+ Lautschrift).
    /// Zeilen ohne Übersetzung und doppelte Vorderseiten werden übersprungen. Kopf mit `#separator`, `#html`, `#columns`.
    static func ankiCSV(_ sessions: [HistorySession], frontLang: String? = nil) -> String {
        var out = "#separator:comma\n#html:true\n#columns:Front,Back,Tags\n#tags column:3\n"
        var seen = Set<String>()
        for r in mergedRows(sessions) {
            let front = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = r.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { continue }
            if let fl = frontLang, !fl.isEmpty, r.lang != fl { continue }
            guard seen.insert(fix(front)).inserted else { continue }
            var b = back
            if !r.translit.isEmpty { b += "\n" + r.translit }
            let tag = "dolmetscher " + (r.lang.isEmpty ? "xx" : r.lang)
            out += [ankiField(front), ankiField(b), ankiField(tag)].joined(separator: ",") + "\n"
        }
        return out
    }

    private static func fix(_ s: String) -> String { s.lowercased() }

    // MARK: Gemeinsamer Untertitel-Export

    /// Zeitachse über mehrere Sitzungen: Pausen werden auf höchstens `maxGap` Sekunden verkürzt.
    static func timeline(_ rows: [HistoryRow], maxGap: Double = 8) -> [Double] {
        var t = 0.0
        var out: [Double] = []
        for (i, r) in rows.enumerated() {
            if i > 0 { t += min(max(0, r.time.timeIntervalSince(rows[i - 1].time)), maxGap) }
            out.append(t)
        }
        return out
    }

    static func subtitles(_ sessions: [HistorySession], vtt: Bool) -> String {
        let rows = mergedRows(sessions).filter { !$0.text.isEmpty || !$0.translation.isEmpty }
        guard !rows.isEmpty else { return "" }
        let starts = timeline(rows)
        var out = vtt ? "WEBVTT\n\n" : ""
        for (i, r) in rows.enumerated() {
            let end = i + 1 < rows.count ? max(starts[i] + 1.0, starts[i + 1] - 0.1) : starts[i] + 4
            let cappedEnd = min(end, starts[i] + 7)
            if !vtt { out += "\(i + 1)\n" }
            out += ExportFormats.timestamp(starts[i], comma: !vtt) + " --> " + ExportFormats.timestamp(cappedEnd, comma: !vtt) + "\n"
            for line in [r.translation, r.text] where !line.isEmpty { out += ExportFormats.cueText(line, vtt: vtt) + "\n" }
            out += "\n"
        }
        return out
    }

    static func markdown(_ sessions: [HistorySession], title: String, timeZone: TimeZone = .current) -> String {
        var out = "# " + ExportFormats.mdEscape(title) + "\n\n"
        for s in sessions {
            out += markdownBody(s, timeZone: timeZone)
        }
        return out
    }

    private static func markdownBody(_ s: HistorySession, timeZone: TimeZone) -> String {
        let md = HistoryLogic.markdown(s, title: s.start.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)),
                                       timeZone: timeZone)
        return "#" + md + "\n"
    }
}

// MARK: - Statistik für das Dashboard

struct R23Stats: Equatable {
    var perLang: [LabelCount] = []
    var perHour = [Int](repeating: 0, count: 24)
    var perWeekday = [Int](repeating: 0, count: 7)     // Montag = 0
    var perSpeaker: [LabelCount] = []
    var perDay: [LabelCount] = []                      // letzte bis zu 14 Tage, älteste zuerst
    var avgConfidence: Double?
    var lowConfidence = 0                              // Konfidenz < 0,6
    var longestSession = 0
    var total = 0

    struct LabelCount: Equatable, Identifiable {
        var label: String
        var count: Int
        var id: String { label }
    }
}

enum R23StatsLogic {
    static func compute(_ sessions: [HistorySession], calendar: Calendar = .current) -> R23Stats {
        var st = R23Stats()
        var langs: [String: Int] = [:], speakers: [String: Int] = [:], days: [String: Int] = [:]
        var confSum = 0.0, confN = 0
        for s in sessions {
            st.longestSession = max(st.longestSession, s.rows.count)
            for r in s.rows {
                st.total += 1
                langs[r.lang.isEmpty ? "?" : r.lang, default: 0] += 1
                let sp = R23History.speakerKey(r)
                if !sp.isEmpty { speakers[sp, default: 0] += 1 }
                let c = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: r.time)
                st.perHour[min(23, max(0, c.hour ?? 0))] += 1
                st.perWeekday[((c.weekday ?? 2) + 5) % 7] += 1       // Sonntag = 1 → 6, Montag = 2 → 0
                days[String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0), default: 0] += 1
                if let conf = r.confidence {
                    confSum += conf; confN += 1
                    if conf < 0.6 { st.lowConfidence += 1 }
                }
            }
        }
        func sorted(_ d: [String: Int]) -> [R23Stats.LabelCount] {
            d.map { R23Stats.LabelCount(label: $0.key, count: $0.value) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
        }
        st.perLang = sorted(langs)
        st.perSpeaker = sorted(speakers)
        st.perDay = days.keys.sorted().suffix(14).map { R23Stats.LabelCount(label: $0, count: days[$0] ?? 0) }
        st.avgConfidence = confN > 0 ? confSum / Double(confN) : nil
        return st
    }
}

// MARK: - „Sensible Sitzung“: nichts speichern, danach alles wie vorher

/// Die drei Schalter, die „nichts wird gespeichert“ ausmachen: privater Modus (keine Anfragen an Übersetzungsdienste mit
/// Klartext in URLs, `--private`), lokaler Verlauf (`--history`) und Textprotokoll (`--log-text`).
struct R23SensitiveFlags: Equatable, Codable {
    var privateMode = false
    var history = false
    var logText = false
}

struct R23SensitiveState: Equatable, Codable {
    var active = false
    var previous = R23SensitiveFlags()
}

enum R23Sensitive {
    static let flags = R23SensitiveFlags(privateMode: true, history: false, logText: false)

    /// Einschalten: Schalter erzwingen und die alten merken (nicht doppelt merken, wenn schon aktiv).
    static func enter(_ s: R23SensitiveState, current: R23SensitiveFlags) -> (state: R23SensitiveState, set: R23SensitiveFlags) {
        if s.active { return (s, flags) }
        return (R23SensitiveState(active: true, previous: current), flags)
    }

    /// Ausschalten: die alten Werte wiederherstellen.
    static func leave(_ s: R23SensitiveState) -> (state: R23SensitiveState, restore: R23SensitiveFlags?) {
        guard s.active else { return (s, nil) }
        return (R23SensitiveState(), s.previous)
    }

    /// Während der Sitzung: hat jemand einen Schalter zurückgestellt (Zurücksetzen, Import, Einstellungen), kommt der
    /// erzwungene Wert zurück. nil = alles in Ordnung.
    static func enforce(_ s: R23SensitiveState, current: R23SensitiveFlags) -> R23SensitiveFlags? {
        guard s.active, current != flags else { return nil }
        return flags
    }
}

// MARK: - Einrichtung: Mikrofon-Test, Kopfhörer, Schlüssel

enum MicVerdict: Equatable { case silent, tooQuiet, good, tooLoud }

enum R23Mic {
    /// Effektivwert (0…1) in dBFS; Stille wird auf −120 begrenzt.
    static func db(rms: Float) -> Float { 20 * log10(max(rms, 1e-6)) }

    /// Anzeige 0…1 für −60…0 dBFS.
    static func meter(db: Float) -> Double { Double(min(1, max(0, (db + 60) / 60))) }

    /// Urteil über den lautesten Pegel der Messung.
    static func verdict(peakDB: Float) -> MicVerdict {
        if peakDB < -55 { return .silent }
        if peakDB < -30 { return .tooQuiet }
        if peakDB > -3 { return .tooLoud }
        return .good
    }
}

enum OutputKind: Equatable { case headphones, speaker, unknown }

enum R23Headphones {
    static func classify(_ name: String) -> OutputKind {
        let n = R23Settings.fold(name)
        let phones = ["kopfhoerer", "kopfhorer", "headphone", "airpods", "buds", "headset", "beats", "earbud", "earphone", "bluetooth"]
        let speakers = ["lautsprecher", "speaker", "display", "hdmi", "tv", "fernseher", "monitor", "soundbar"]
        if phones.contains(where: { n.contains($0) }) { return .headphones }
        if speakers.contains(where: { n.contains($0) }) { return .speaker }
        return .unknown
    }

    /// Lautsprecher + Mikrofon im selben Gerät/Raum: die App hört ihre eigene Stimme (Rückkopplung, Doppelblasen).
    static func hintNeeded(output: OutputKind, speakEnabled: Bool) -> Bool {
        speakEnabled && output != .headphones
    }
}

enum KeyFormat: Equatable { case empty, tooShort, badPrefix, ok }
enum KeyCheckResult: Equatable { case valid, rejected, rateLimited, serverError, offline, unexpected(Int) }

enum R23Key {
    static func normalize(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nur die Form, ohne Netz: Anthropic-Schlüssel beginnen mit „sk-ant-“.
    static func format(_ s: String) -> KeyFormat {
        let k = normalize(s)
        if k.isEmpty { return .empty }
        if !k.hasPrefix("sk-ant-") { return .badPrefix }
        if k.count < 24 || k.contains(" ") { return .tooShort }
        return .ok
    }

    /// HTTP-Status der Testanfrage; nil = kein Netz.
    static func result(status: Int?) -> KeyCheckResult {
        guard let s = status else { return .offline }
        switch s {
        case 200..<300: return .valid
        case 401, 403: return .rejected
        case 429: return .rateLimited
        case 500..<600: return .serverError
        default: return .unexpected(s)
        }
    }
}

// MARK: - Erstinstallation: Vorab-Prüfung, Restzeit

enum NetState: Equatable { case online, offline, unknown }
enum PreflightIssue: Equatable { case lowSpace(neededGB: Double, freeGB: Double), noNetwork }

enum R23Preflight {
    static func evaluate(freeBytes: Int64?, requiredGB: Double, network: NetState, needsDownload: Bool) -> [PreflightIssue] {
        var out: [PreflightIssue] = []
        if needsDownload, network == .offline { out.append(.noNetwork) }
        if let f = freeBytes, requiredGB > 0 {
            let free = Double(f) / 1_073_741_824
            if free < requiredGB { out.append(.lowSpace(neededGB: requiredGB, freeGB: free)) }
        }
        return out
    }
}

/// Restzeit aus den letzten Messpunkten (gleitendes Fenster, damit eine langsame Anfangsphase nicht ewig nachwirkt).
struct R23ETA {
    private(set) var samples: [(t: TimeInterval, done: Double)] = []
    let window: Int

    init(window: Int = 8) { self.window = max(2, window) }

    mutating func add(done: Double, at t: TimeInterval) {
        if let l = samples.last, t <= l.t { return }
        samples.append((t, done))
        if samples.count > window { samples.removeFirst(samples.count - window) }
    }

    /// Sekunden bis `total`; nil bei zu wenig Daten oder Stillstand.
    func remaining(total: Double) -> TimeInterval? {
        guard let a = samples.first, let b = samples.last, b.t > a.t else { return nil }
        let speed = (b.done - a.done) / (b.t - a.t)
        guard speed > 0, b.done < total else { return b.done >= total ? 0 : nil }
        return (total - b.done) / speed
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        if s < 60 { return "< 1 min" }
        if s < 3600 { return "\(Int((Double(s) / 60).rounded(.up))) min" }
        return String(format: "%d h %02d min", s / 3600, (s % 3600) / 60)
    }
}

// MARK: - Menü: Tastenkürzel-Konflikte, Sperrbildschirm, Problem melden, letzte Übersetzung

struct R23HotKeyConflict: Equatable {
    let actionID: Int
    let letter: Character
    let reason: Reason
    let suggestion: Character?
    enum Reason: Equatable { case takenByOtherApp, invalid, voiceOver, unknown(Int32) }
}

enum R23HotKeys {
    static let eventHotKeyExists: Int32 = -9878
    static let eventHotKeyInvalid: Int32 = -9879

    static func reason(status: Int32) -> R23HotKeyConflict.Reason {
        switch status {
        case eventHotKeyExists: return .takenByOtherApp
        case eventHotKeyInvalid: return .invalid
        default: return .unknown(status)
        }
    }

    /// Fehlgeschlagene Registrierungen → Konflikte mit Vorschlag eines freien Buchstabens (nicht vergeben, nicht
    /// ebenfalls fehlgeschlagen). Bei laufendem VoiceOver kommt ein Hinweis dazu: ⌃⌥ ist dessen Tastenkombination.
    static func conflicts(failures: [(id: Int, status: Int32)], configured: [Int: Character],
                          voiceOver: Bool) -> [R23HotKeyConflict] {
        let used = Set(configured.values)
        let failedLetters = Set(failures.compactMap { configured[$0.id] })
        var free = HotKeyLogic.letters.filter { !used.contains($0) && !failedLetters.contains($0) }
        var out: [R23HotKeyConflict] = []
        for f in failures.sorted(by: { $0.id < $1.id }) {
            guard let letter = configured[f.id] else { continue }
            let sug = free.isEmpty ? nil : free.removeFirst()
            out.append(R23HotKeyConflict(actionID: f.id, letter: letter, reason: reason(status: f.status), suggestion: sug))
        }
        if voiceOver, let first = configured.sorted(by: { $0.key < $1.key }).first {
            out.append(R23HotKeyConflict(actionID: first.key, letter: first.value, reason: .voiceOver, suggestion: nil))
        }
        return out
    }
}

/// Mikrofon beim Sperren des Bildschirms anhalten und danach nur dann fortsetzen, wenn wir es angehalten haben.
struct R23LockPause: Equatable {
    var autoPaused = false

    mutating func locked(active: Bool, paused: Bool, enabled: Bool) -> Bool {
        guard enabled, active, !paused, !autoPaused else { return false }
        autoPaused = true
        return true
    }

    /// true = jetzt fortsetzen. War zwischenzeitlich schon jemand anderes dran (Nutzer hat selbst fortgesetzt), nichts tun.
    mutating func unlocked(paused: Bool) -> Bool {
        defer { autoPaused = false }
        return autoPaused && paused
    }
}

enum R23Report {
    static let issuesURL = "https://github.com/Pschmetzer/en-th-dolmetscher/issues/new"

    /// Vorbefüllte Fehlermeldung. Enthält nur Version, System und Oberflächensprache, nie Gespräche, Schlüssel oder Pfade.
    static func url(version: String, build: String, macOS: String, chip: String, uiLang: String,
                    note: String = "") -> URL? {
        var body = "**Was ist passiert?**\n\n\n**Was hast du erwartet?**\n\n\n---\n"
        body += "App: \(version) (\(build))\nmacOS: \(macOS)\nChip: \(chip)\nOberfläche: \(uiLang)\n"
        if !note.isEmpty { body += note + "\n" }
        var c = URLComponents(string: issuesURL)
        c?.queryItems = [URLQueryItem(name: "title", value: "[Mac] "), URLQueryItem(name: "body", value: String(body.prefix(1500)))]
        return c?.url
    }
}

enum R23Menu {
    /// Letzte Übersetzung als einzeilige Menüzeile (Zeichen, nicht Bytes: Thai wird nicht mitten im Zeichen getrennt).
    static func title(_ text: String?, limit: Int = 48) -> String? {
        guard let text else { return nil }
        let flat = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
