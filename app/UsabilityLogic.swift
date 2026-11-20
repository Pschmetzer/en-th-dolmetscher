// UsabilityLogic.swift – kleine, reine Logikbausteine der Runde 22 (nur Foundation; getestet in swift-tests).
// Eingabeverlauf, Zeitstempel-Trenner, Suchtreffer, Kopier-Texte, Schnellsatz-Aufbereitung, Fehlerprotokoll,
// Neustart-Backoff, Schreibfehler-Meldungen, Glossar-Sicherung, Mikrofon-Zustand, Barrierefreiheit-Texte, Statistik-Text.
import Foundation

// MARK: Eingabeverlauf (↑/↓ im Eingabefeld)

/// Verlauf getippter Sätze. ↑ holt ältere, ↓ neuere Einträge; der angefangene Entwurf bleibt erhalten.
struct InputHistory: Equatable {
    static let capacity = 50
    private(set) var entries: [String] = []
    private var cursor: Int?          // nil = nicht im Verlauf (Entwurf wird angezeigt)
    private var stash = ""            // Entwurf vor dem ersten ↑

    /// Satz merken: leer/Leerraum ignorieren, direkte Wiederholung nicht doppelt, ältere Dublette nach hinten ziehen.
    mutating func push(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        cursor = nil; stash = ""
        guard !t.isEmpty else { return }
        entries.removeAll { $0 == t }
        entries.append(t)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    /// ↑: nächstältere Eintrag; nil, wenn es nichts (Älteres) gibt.
    mutating func up(current: String) -> String? {
        guard !entries.isEmpty else { return nil }
        if let c = cursor {
            guard c > 0 else { return nil }
            cursor = c - 1
        } else {
            stash = current
            cursor = entries.count - 1
        }
        return entries[cursor!]
    }

    /// ↓: nächstneuerer Eintrag, am Ende der Entwurf; nil, wenn man nicht im Verlauf ist.
    mutating func down() -> String? {
        guard let c = cursor else { return nil }
        if c + 1 < entries.count { cursor = c + 1; return entries[c + 1] }
        cursor = nil
        return stash
    }

    mutating func resetCursor() { cursor = nil; stash = "" }
}

// MARK: Zeitstempel-Trenner

enum TimeDivider {
    /// Ab dieser Pause (Sekunden) steht ein Zeit-Trenner zwischen zwei Blasen.
    static let gap: TimeInterval = 600

    /// Trenner vor `current`? Ja beim ersten Eintrag nie, bei Tageswechsel oder Pause ≥ `gap`.
    static func needsDivider(previous: Date?, current: Date, calendar: Calendar = .current) -> Bool {
        guard let p = previous else { return false }
        if !calendar.isDate(p, inSameDayAs: current) { return true }
        return current.timeIntervalSince(p) >= gap
    }

    /// Beschriftung: nur Uhrzeit am selben Tag, sonst Datum und Uhrzeit.
    static func label(_ d: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale; f.calendar = calendar; f.timeZone = calendar.timeZone
        if calendar.isDate(d, inSameDayAs: now) { f.dateStyle = .none; f.timeStyle = .short }
        else { f.dateStyle = .medium; f.timeStyle = .short }
        return f.string(from: d)
    }
}

// MARK: Suche mit Trefferzähler

enum SearchHits {
    private static let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Anzahl nicht überlappender Vorkommen von `query` in `text` (Groß-/Kleinschreibung und Akzente egal).
    static func occurrences(of query: String, in text: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return 0 }
        var n = 0
        var from = text.startIndex
        while from < text.endIndex, let r = text.range(of: q, options: opts, range: from..<text.endIndex) {
            n += 1
            from = r.upperBound
        }
        return n
    }

    /// Gesamtvorkommen über mehrere Texte.
    static func total(of query: String, in texts: [String]) -> Int {
        texts.reduce(0) { $0 + occurrences(of: query, in: $1) }
    }

    /// Nächster/vorheriger Treffer, am Rand umlaufend. `count == 0` → nil.
    static func step(current: Int?, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let c = current else { return forward ? 0 : count - 1 }
        return forward ? (c + 1) % count : (c - 1 + count) % count
    }

    /// „2 / 7“ – Anzeige des aktuellen Treffers (1-basiert); ohne aktuellen Treffer nur die Gesamtzahl.
    static func positionLabel(current: Int?, count: Int) -> String {
        guard count > 0 else { return "0" }
        guard let c = current, c >= 0, c < count else { return String(count) }
        return "\(c + 1) / \(count)"
    }
}

// MARK: Kopier-Texte (Kontextmenü)

enum BubbleCopy {
    enum Mode { case original, translation, both }

    static func text(original: String, translation: String, mode: Mode, translated: Bool = true) -> String {
        switch mode {
        case .original: return original
        case .translation: return translated && !translation.isEmpty ? translation : original
        case .both:
            guard translated, !translation.isEmpty else { return original }
            return original + "\n" + translation
        }
    }

    /// Mit Sprecher und Uhrzeit: „[14:32] Anna: Text“.
    static func withMeta(_ body: String, speaker: String?, date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let stamp = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        let who = (speaker?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 + ": " } ?? ""
        return "[\(stamp)] " + who + body
    }
}

// MARK: Schnellsätze

enum QuickPhraseLogic {
    static let maxLength = 200

    /// Leerraum glätten, Zeilenumbrüche zu Leerzeichen, auf 200 Zeichen kürzen. nil bei leerem Ergebnis.
    static func normalize(_ s: String) -> String? {
        let flat = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        return String(flat.prefix(maxLength))
    }

    static func contains(_ list: [String], _ phrase: String) -> Bool {
        let key = phrase.lowercased()
        return list.contains { $0.lowercased() == key }
    }

    enum Outcome: Equatable { case added(String), duplicate, empty }

    /// Satz an die Liste (Zeilentext) anhängen; Ergebnis plus neuer Gesamttext.
    static func add(_ phrase: String, to current: String) -> (Outcome, String) {
        guard let p = normalize(phrase) else { return (.empty, current) }
        let existing = current.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if contains(existing, p) { return (.duplicate, current) }
        return (.added(p), (existing + [p]).joined(separator: "\n"))
    }
}

// MARK: Fehlerprotokoll (Diagnosefenster)

struct ErrorLogEntry: Equatable {
    let date: Date
    let message: String
    var count = 1
}

struct ErrorLog: Equatable {
    static let capacity = 50
    private(set) var entries: [ErrorLogEntry] = []

    /// Neuer Fehler. Gleiche Meldung kurz nach der letzten (≤ 60 s) erhöht nur den Zähler.
    mutating func record(_ message: String, at date: Date = Date()) {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        if var last = entries.last, last.message == m, date.timeIntervalSince(last.date) <= 60 {
            last.count += 1
            entries[entries.count - 1] = last
            return
        }
        entries.append(ErrorLogEntry(date: date, message: m))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    mutating func clear() { entries.removeAll() }

    /// Textform, neueste zuerst, höchstens `limit` Zeilen: „2026-01-02T10:00:00Z (×3) Meldung“.
    func formatted(limit: Int = 20) -> String {
        let iso = ISO8601DateFormatter()
        return entries.suffix(limit).reversed().map { e in
            iso.string(from: e.date) + (e.count > 1 ? " (×\(e.count))" : "") + " " + e.message
        }.joined(separator: "\n")
    }
}

// MARK: Neustart-Backoff

enum RestartBackoff {
    static let maxDelay: TimeInterval = 30

    /// Wartezeit vor Versuch `attempt` (1-basiert): 1, 2, 4, 8 … gedeckelt auf `maxDelay`; ungültige Werte → 1 s.
    static func delay(attempt: Int, cap: TimeInterval = maxDelay) -> TimeInterval {
        guard attempt >= 1 else { return 1 }
        let exp = min(attempt - 1, 20)
        return min(cap, pow(2, Double(exp)))
    }
}

// MARK: Schreibfehler (API-Schlüssel an die Engine, Protokoll-Rotation)

enum WriteFailure {
    /// Kurze, schlüsselfreie Beschreibung eines Fehlers (nie den Fehlertext mit Daten weitergeben).
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }

    /// Meldung nach fehlgeschlagener Rotation: Anzahl und erster Dateiname (ohne Verzeichnis).
    static func rotationSummary(failedPaths: [String]) -> String? {
        guard let first = failedPaths.first else { return nil }
        let name = (first as NSString).lastPathComponent
        return failedPaths.count == 1 ? name : "\(name) +\(failedPaths.count - 1)"
    }
}

// MARK: Glossar-Sicherung

enum GlossaryBackup {
    /// Vor dem Überschreiben eine .bak anlegen, wenn die bisherige Datei Inhalt hat und sich der Inhalt ändert.
    /// Eine leere/fehlende Datei ersetzt nie eine gute Sicherung.
    static func shouldBackup(existing: Data?, new: Data) -> Bool {
        guard let e = existing, !e.isEmpty else { return false }
        return e != new
    }

    static func backupURL(for url: URL) -> URL { url.appendingPathExtension("bak") }
}

// MARK: Mikrofon-Berechtigung

enum MicPermission: Equatable {
    case notAsked, allowed, denied, restricted, unknown

    /// Zuordnung aus `AVAuthorizationStatus.rawValue` (0 offen, 1 eingeschränkt, 2 abgelehnt, 3 erlaubt).
    static func from(rawStatus: Int) -> MicPermission {
        switch rawStatus {
        case 0: return .notAsked
        case 1: return .restricted
        case 2: return .denied
        case 3: return .allowed
        default: return .unknown
        }
    }

    /// Erklärung/Schlüssel für die Oberfläche; nil = nichts anzuzeigen.
    var hintKey: String? {
        switch self {
        case .denied: return "mic_perm_denied"
        case .restricted: return "mic_perm_restricted"
        case .notAsked: return "mic_perm_notasked"
        default: return nil
        }
    }

    /// Kann die Nutzerin es in den Systemeinstellungen selbst ändern?
    var canOpenSettings: Bool { self == .denied || self == .notAsked }
    var detail: String {
        switch self {
        case .notAsked: return "not asked"
        case .allowed: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .unknown: return "unknown"
        }
    }
}

// MARK: Barrierefreiheit

enum A11yBubble {
    /// Position „3 von 12“ für VoiceOver (1-basiert); nil bei ungültigen Werten.
    static func position(index: Int, total: Int) -> String? {
        guard total > 0, index >= 0, index < total else { return nil }
        return "\(index + 1)/\(total)"
    }

    /// Hochkontrast-/„Ohne Farbe unterscheiden“-Marker: Sprachkürzel plus Richtungssymbol, unabhängig von der Farbe.
    static func marker(lang: String, mine: Bool) -> String {
        (mine ? "◀ " : "▶ ") + lang.uppercased()
    }

    /// Uhrzeit für das VoiceOver-Label („14:32“).
    static func clock(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: Statistik / Export-Optionen

enum SessionStats {
    struct Summary: Equatable {
        var count = 0
        var words = 0
        var seconds: TimeInterval = 0     // Spanne erste bis letzte Äußerung
        var byLang: [String: Int] = [:]
    }

    static func summarize(_ rows: [(lang: String, text: String, date: Date)]) -> Summary {
        var s = Summary()
        s.count = rows.count
        for r in rows {
            s.words += r.text.split(whereSeparator: { $0.isWhitespace }).count
            s.byLang[r.lang, default: 0] += 1
        }
        if let a = rows.map({ $0.date }).min(), let b = rows.map({ $0.date }).max() { s.seconds = b.timeIntervalSince(a) }
        return s
    }

    /// „1 h 05 min“ / „7 min“ / „< 1 min“.
    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(max(0, seconds) / 60)
        if m < 1 { return "< 1 min" }
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h " + String(format: "%02d", m % 60) + " min"
    }

    /// Eine Zeile für Zwischenablage/Export-Kopf, z. B. „12 Äußerungen · 140 Wörter · 7 min · EN 6, TH 6“.
    static func line(_ s: Summary, utterances: String, words: String) -> String {
        let langs = s.byLang.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key.uppercased()) \($0.value)" }.joined(separator: ", ")
        var parts = ["\(s.count) \(utterances)", "\(s.words) \(words)", duration(s.seconds)]
        if !langs.isEmpty { parts.append(langs) }
        return parts.joined(separator: " · ")
    }
}

/// Auswahl beim Export: nur eine Sprache, ohne Uhrzeiten.
struct ExportOptions: Equatable {
    var onlyLang: String? = nil
    var includeTimes = true

    func keep(lang: String) -> Bool { onlyLang == nil || onlyLang == lang }
}
