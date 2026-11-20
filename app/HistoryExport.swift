// HistoryExport.swift – eine Verlaufssitzung als Markdown oder CSV (reine Logik, Foundation + HistoryLogic + ExportFormats).
import Foundation

extension HistoryLogic {
    /// Sitzung als Markdown mit Zeitstempeln: Überschrift, je Zeile `**HH:mm:ss · DE**: Text` und die Übersetzung darunter.
    /// `timeFormat`/`locale` sind einstellbar, damit der Test unabhängig von Zeitzone und Systemsprache ist.
    static func markdown(_ s: HistorySession, title: String, timeZone: TimeZone = .current) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        df.timeZone = timeZone
        df.locale = Locale(identifier: "en_US_POSIX")
        var out = "# " + ExportFormats.mdEscape(title) + "\n\n"
        for r in s.rows {
            let who = r.lang.isEmpty ? "?" : r.lang.uppercased()
            out += "**\(df.string(from: r.time)) · \(who)**: \(ExportFormats.mdEscape(r.text))  \n"
            if !r.translation.isEmpty { out += "→ \(ExportFormats.mdEscape(r.translation))\n" }
            if !r.translit.isEmpty { out += "_\(ExportFormats.mdEscape(r.translit))_\n" }
            out += "\n"
        }
        return out
    }

    /// Sitzung als CSV (ISO-8601-Zeit, Formel-sichere Zellen).
    static func csv(_ s: HistorySession) -> String {
        let iso = ISO8601DateFormatter()
        var out = "time,lang,text,translation,translit,provider,speaker\n"
        for r in s.rows {
            out += [iso.string(from: r.time), r.lang, r.text, r.translation, r.translit, r.provider ?? "", r.speaker ?? ""]
                .map(ExportFormats.csvCell).joined(separator: ",") + "\n"
        }
        return out
    }
}
