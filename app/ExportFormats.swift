// ExportFormats.swift – reine Formatierung für den Gesprächs-Export (ohne UI/Engine; per swiftc getestet).
import Foundation

/// Eine Äußerung, wie der Export sie braucht. `at` ist der Ankunftszeitpunkt, `dur`/`readyS` aus `utt.dur`/`utt.ready_s`.
struct ExportItem: Equatable {
    var at: Date
    var lang: String
    var to: String
    var text: String
    var out: String
    var translated: Bool
    var speaker: String?
    var dur: Double?
    var readyS: Double?
}

enum ExportFormats {
    /// Markdown-Sonderzeichen maskieren; Zeilenumbrüche werden harte Umbrüche („  \n“).
    static func mdEscape(_ s: String) -> String {
        var o = ""
        for ch in s {
            if ch == "\n" || ch == "\r\n" || ch == "\r" { o += "  \n"; continue }
            if "\\`*_#>[]<|~".contains(ch) { o.append("\\") }
            o.append(ch)
        }
        return o
    }

    /// CSV-Feld in Anführungszeichen; Anfang mit = + - @ Tab CR bekommt ein ' (keine Formel in Tabellenkalkulationen).
    static func csvCell(_ v: String) -> String {
        var t = v
        if let f = t.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(f) { t = "'" + t }
        return "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Zeitstempel `HH:MM:SS,mmm` (SRT) bzw. `HH:MM:SS.mmm` (WebVTT).
    static func timestamp(_ seconds: Double, comma: Bool) -> String {
        let ms = Int((max(0, seconds) * 1000).rounded())
        let sep = comma ? "," : "."
        return String(format: "%02d:%02d:%02d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60)
            + sep + String(format: "%03d", ms % 1000)
    }

    /// Untertitel-Zeiten je Äußerung: Beginn = Ankunft − Bereitzeit − Länge, Ende nie in den nächsten Untertitel hinein.
    static func cues(_ items: [ExportItem]) -> [(start: Double, end: Double)] {
        guard let t0 = items.first?.at else { return [] }
        var r: [(start: Double, end: Double)] = []
        for (i, u) in items.enumerated() {
            let arrived = u.at.timeIntervalSince(t0)
            let start = max(0, u.dur.map { arrived - (u.readyS ?? 0) - $0 } ?? arrived)
            let guess = max(2, min(7, Double(max(u.text.count, u.out.count)) / 14))
            var end = start + (u.dur.map { max(1, $0) } ?? guess)
            if i + 1 < items.count { end = min(end, items[i + 1].at.timeIntervalSince(t0) - 0.1) }
            r.append((start, max(end, start + 0.5)))
        }
        return r
    }

    /// Untertiteltext: leere Zeilen würden den Block beenden, „-->“ einen Zeitstempel vortäuschen; WebVTT kennt < und &.
    static func cueText(_ s: String, vtt: Bool) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        t = t.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).joined(separator: "\n")
        t = t.replacingOccurrences(of: "-->", with: "–>")
        if vtt {
            t = t.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        }
        return t
    }

    private static func subtitles(_ items: [ExportItem], vtt: Bool) -> String {
        guard !items.isEmpty else { return "" }
        var s = vtt ? "WEBVTT\n\n" : ""
        for (i, (u, c)) in zip(items, cues(items)).enumerated() {
            if !vtt { s += "\(i + 1)\n" }
            s += timestamp(c.start, comma: !vtt) + " --> " + timestamp(c.end, comma: !vtt) + "\n"
            let who = u.speaker.map { cueText($0, vtt: vtt) }.flatMap { $0.isEmpty ? nil : "[\($0)] " } ?? ""
            s += who + cueText(u.text, vtt: vtt) + "\n"
            if u.translated, !cueText(u.out, vtt: vtt).isEmpty { s += cueText(u.out, vtt: vtt) + "\n" }
            s += "\n"
        }
        return s
    }

    static func srt(_ items: [ExportItem]) -> String { subtitles(items, vtt: false) }
    static func webvtt(_ items: [ExportItem]) -> String { subtitles(items, vtt: true) }

    /// Nur Äußerungen im Zeitraum [from, to]; nil = offen.
    static func filter(_ items: [ExportItem], from: Date?, to: Date?) -> [ExportItem] {
        items.filter { u in (from.map { u.at >= $0 } ?? true) && (to.map { u.at <= $0 } ?? true) }
    }

    /// Dateiname mit Datum, ohne Zeichen, die Dateisysteme stören (/ : \ und Steuerzeichen).
    static func fileName(base: String, date: Date, ext: String) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                           c.hour ?? 0, c.minute ?? 0)
        let bad = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        var b = base.unicodeScalars.map { bad.contains($0) ? " " : String($0) }.joined()
        b = b.trimmingCharacters(in: .whitespaces)
        if b.isEmpty { b = "export" }
        return b + " " + stamp + "." + ext
    }

    /// Dateiinhalt als UTF-8-Daten; CSV mit BOM, damit Excel Thai und Umlaute nicht als Windows-1252 liest.
    static func fileData(_ text: String, csv: Bool) -> Data {
        Data(((csv ? "\u{FEFF}" : "") + text).utf8)
    }
}
