// Round35.swift – Runde 35: kleine, reine Logik-Bausteine (ohne Systemaufrufe, testbar ohne Gerät):
// Barrierefreiheit, Fehlerklassen und Wiederholung, Speicher, Zeitangaben, Sprachwahl, Textsäuberung, Aufbewahrung.
// Alles Foundation-only; die Oberflächen binden die Bausteine später an.
import Foundation

// MARK: 1. VoiceOver: Beschriftung einer Sprechblase

enum R35Accessibility {
    /// "Ich, 14:05: Hallo". Leere Texte liefern "Ich, 14:05: leer" nicht, sondern nur den Sprecher.
    static func bubbleLabel(speaker: String, text: String, time: String?) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var head = speaker
        if let time, !time.isEmpty { head += ", " + time }
        return t.isEmpty ? head : head + ": " + t
    }

    // MARK: 2. Sicherheit nicht nur über Farbe

    enum Confidence: String, Equatable, Sendable { case low, medium, high }

    /// Erkennungssicherheit (0...1) als Stufe, damit sie auch ohne Farbe vorgelesen werden kann.
    static func confidence(_ value: Double) -> Confidence {
        let v = value.isNaN ? 0 : value
        if v < 0.5 { return .low }
        if v < 0.8 { return .medium }
        return .high
    }

    // MARK: 3. Schriftgröße begrenzen

    /// Skaliert eine Größe mit dem Faktor der Systemschrift, begrenzt auf [minimum, maximum].
    static func clampedSize(base: Double, scale: Double, minimum: Double, maximum: Double) -> Double {
        let lo = Swift.min(minimum, maximum), hi = Swift.max(minimum, maximum)
        let s = scale.isFinite && scale > 0 ? scale : 1
        return Swift.min(hi, Swift.max(lo, base * s))
    }

    // MARK: 4. Bewegung reduzieren

    /// Dauer einer Animation; bei "Bewegung reduzieren" keine.
    static func animationDuration(_ base: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : Swift.max(0, base)
    }
}

// MARK: 5. Warteschlange für Offline-Übersetzungen

/// Texte, die ohne Verbindung nicht übersetzt werden konnten. Begrenzt, ohne Dopplung, ältester zuerst.
struct R35RetryQueue: Codable, Equatable, Sendable {
    private(set) var items: [String] = []
    let limit: Int

    init(limit: Int = 20) { self.limit = Swift.max(1, limit) }

    /// Hängt hinten an. Gleicher Text (nach Trimmen) rückt nur nach hinten. Ist die Queue voll, fällt der älteste weg.
    @discardableResult
    mutating func add(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        items.removeAll { $0 == t }
        items.append(t)
        while items.count > limit { items.removeFirst() }
        return true
    }

    mutating func next() -> String? { items.isEmpty ? nil : items.removeFirst() }
    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
}

// MARK: 6./7. Fehlerklassen und Wiederholung

enum R35ErrorKind: String, Equatable, Sendable {
    case offline, timeout, tls, cancelled, server, auth, quota, unknown

    /// Nur Fehler, die sich von selbst beheben können, lohnen eine Wiederholung.
    var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .server: return true
        case .tls, .cancelled, .auth, .quota, .unknown: return false
        }
    }

    /// NSURLErrorDomain-Codes und HTTP-Status. `domain` "http" meint einen Status (200...599).
    static func classify(domain: String, code: Int) -> R35ErrorKind {
        if domain == "http" {
            switch code {
            case 401, 403: return .auth
            case 402, 429: return .quota
            case 408: return .timeout
            case 500...599: return .server
            default: return .unknown
            }
        }
        guard domain == NSURLErrorDomain else { return .unknown }
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
             NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return .offline
        case NSURLErrorTimedOut: return .timeout
        case NSURLErrorCancelled: return .cancelled
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid:
            return .tls
        default: return .unknown
        }
    }

    static func classify(_ error: Error) -> R35ErrorKind {
        let e = error as NSError
        return classify(domain: e.domain, code: e.code)
    }
}

enum R35Backoff {
    /// Wartezeit vor Versuch `attempt` (0 = erster Wiederholversuch): base * 2^attempt, gedeckelt. Ohne Zufall, damit testbar.
    static func delay(attempt: Int, base: Double = 1, cap: Double = 30) -> Double {
        let a = Swift.min(Swift.max(0, attempt), 20)
        return Swift.min(Swift.max(0, cap), Swift.max(0, base) * Double(1 << a))
    }

    static func shouldRetry(_ kind: R35ErrorKind, attempt: Int, maxAttempts: Int = 3) -> Bool {
        kind.isRetryable && attempt < maxAttempts
    }
}

// MARK: 8./9. Speicher

enum R35Storage {
    enum Verdict: String, Equatable, Sendable { case ok, low, critical }

    /// Reicht der freie Platz für einen Download? `critical` = es passt nicht; `low` = es passt, aber weniger als 20 % Reserve.
    static func verdict(freeBytes: Int64, requiredBytes: Int64) -> Verdict {
        let need = Swift.max(0, requiredBytes)
        if freeBytes < need { return .critical }
        if Double(freeBytes) < Double(need) * 1.2 { return .low }
        return .ok
    }

    /// "950 KB", "1.4 GB": dezimal (1000), eine Nachkommastelle ab MB, immer mit Punkt.
    static func format(_ bytes: Int64) -> String {
        let b = Double(Swift.max(0, bytes))
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = b, i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        if i <= 1 { return String(Int(v.rounded())) + " " + units[i] }
        let tenths = Int((v * 10).rounded())
        return String(tenths / 10) + "." + String(tenths % 10) + " " + units[i]
    }
}

// MARK: 10. Zeitangaben

enum R35Clock {
    /// "02:03" bzw. "1:02:03".
    static func format(seconds: Int) -> String {
        let s = Swift.max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        func two(_ n: Int) -> String { n < 10 ? "0" + String(n) : String(n) }
        return h > 0 ? String(h) + ":" + two(m) + ":" + two(sec) : two(m) + ":" + two(sec)
    }

    /// Für VoiceOver: "1 Stunde 2 Minuten". Nur de und en; sonst en. Sekunden nur unter einer Minute.
    static func spoken(seconds: Int, lang: String) -> String {
        let s = Swift.max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        let de = lang == "de"
        func unit(_ n: Int, _ one: String, _ many: String) -> String { String(n) + " " + (n == 1 ? one : many) }
        var parts: [String] = []
        if h > 0 { parts.append(de ? unit(h, "Stunde", "Stunden") : unit(h, "hour", "hours")) }
        if m > 0 { parts.append(de ? unit(m, "Minute", "Minuten") : unit(m, "minute", "minutes")) }
        if h == 0 && m == 0 { parts.append(de ? unit(sec, "Sekunde", "Sekunden") : unit(sec, "second", "seconds")) }
        return parts.joined(separator: " ")
    }

    /// Ruhezeit [start, end) in vollen Stunden; über Mitternacht erlaubt (22 bis 7). start == end heißt: nie.
    static func isQuiet(hour: Int, start: Int, end: Int) -> Bool {
        let h = ((hour % 24) + 24) % 24, a = ((start % 24) + 24) % 24, b = ((end % 24) + 24) % 24
        if a == b { return false }
        return a < b ? (h >= a && h < b) : (h >= a || h < b)
    }
}

// MARK: 11. Sprachwahl

enum R35Locale {
    /// Beste unterstützte Oberflächensprache für die Wunschliste des Geräts ("zh-Hans-CN" -> "zh-Hans", "de-AT" -> "de").
    /// Ohne Treffer `fallback`.
    static func resolve(preferred: [String], supported: [String], fallback: String = "en") -> String {
        let lowered = supported.map { ($0, $0.lowercased()) }
        for p in preferred {
            let id = p.replacingOccurrences(of: "_", with: "-").lowercased()
            if let exact = lowered.first(where: { $0.1 == id }) { return exact.0 }
            // von hinten kürzen: zh-hans-cn -> zh-hans -> zh
            var parts = id.split(separator: "-").map(String.init)
            while parts.count > 1 {
                parts.removeLast()
                let cand = parts.joined(separator: "-")
                if let hit = lowered.first(where: { $0.1 == cand }) { return hit.0 }
            }
            // zh-TW u. ä. ohne Schrift: Sprache allein, wenn genau eine Variante unterstützt wird
            if let lang = parts.first {
                let same = lowered.filter { $0.1 == lang || $0.1.hasPrefix(lang + "-") }
                if same.count == 1 { return same[0].0 }
            }
        }
        return fallback
    }
}

// MARK: 12./13. Text kürzen und säubern

enum R35Text {
    /// Kürzt nach Zeichen (Graphemen, also ohne Thai-Zeichen oder Emoji zu zerreißen) und hängt "…" an.
    static func truncate(_ s: String, maxChars: Int) -> String {
        let n = Swift.max(1, maxChars)
        guard s.count > n else { return s }
        if n == 1 { return "…" }
        return String(s.prefix(n - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Entfernt Steuerzeichen (außer Zeilenumbruch und Tab) und Unicode-Richtungsumschalter, die Text beim Teilen
    /// umdrehen oder verstecken könnten; Nullbreiten-Zeichen bleiben (Thai braucht sie nicht, Emoji-Folgen schon).
    static func sanitized(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            let v = u.value
            if v == 0x0A || v == 0x09 { out.append(u); continue }
            if v < 0x20 || (v >= 0x7F && v <= 0x9F) { continue }
            if (v >= 0x202A && v <= 0x202E) || (v >= 0x2066 && v <= 0x2069) { continue }
            out.append(u)
        }
        return String(out)
    }

    /// Teilen-Text: "1. Quelle\n   Ziel", Zeilen gesäubert, leere Paare übersprungen.
    static func shareText(pairs: [(source: String, target: String)]) -> String {
        var lines: [String] = []
        var n = 0
        for p in pairs {
            let s = sanitized(p.source).trimmingCharacters(in: .whitespacesAndNewlines)
            let t = sanitized(p.target).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty && t.isEmpty { continue }
            n += 1
            lines.append(String(n) + ". " + s)
            if !t.isEmpty { lines.append("   " + t) }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: 14. Aufbewahrung des Verlaufs

enum R35Retention {
    /// Indizes (aufsteigend), die bleiben: nicht älter als `maxAgeDays` (0 = unbegrenzt) und höchstens die neuesten `maxCount`.
    static func keep(dates: [Date], now: Date, maxAgeDays: Int, maxCount: Int) -> [Int] {
        var idx = Array(dates.indices)
        if maxAgeDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
            idx = idx.filter { dates[$0] >= cutoff }
        }
        if maxCount > 0, idx.count > maxCount {
            let newest = idx.sorted { dates[$0] > dates[$1] || (dates[$0] == dates[$1] && $0 > $1) }.prefix(maxCount)
            idx = Array(newest).sorted()
        }
        return idx
    }
}

// MARK: 15. Entprellen

enum R35Debounce {
    /// Darf eine Aktion jetzt laufen? Erste immer; danach erst nach `interval` Sekunden. Rückwärtslaufende Uhr: ja.
    static func shouldFire(last: Date?, now: Date, interval: Double) -> Bool {
        guard let last else { return true }
        let d = now.timeIntervalSince(last)
        return d < 0 || d >= Swift.max(0, interval)
    }
}

// MARK: 16. Versionsvergleich

enum R35Version {
    /// -1, 0, 1 für "1.10.0" gegen "1.9.2"; fehlende Teile zählen als 0, Nicht-Ziffern als 0.
    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { (part: Substring) -> Int in Int(part.prefix(while: { ch in ch.isNumber })) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<Swift.max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q ? -1 : 1 }
        }
        return 0
    }
}
