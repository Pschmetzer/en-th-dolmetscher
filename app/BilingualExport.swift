// BilingualExport.swift – Verlaufssitzung zweispaltig (Thai | Latein) als Markdown-Tabelle und als druckbares HTML (Grundlage
// des PDF-Exports). Welche Seite Thai ist, entscheidet die Schrift, nicht die Richtung: so steht Thai immer links.
// Reine Logik (Foundation + HistoryLogic + ExportFormats); getestet in swift-tests.
import Foundation

struct BilingualRow: Equatable {
    var time: Date
    var thai: String
    var latin: String
    var translit: String
}

struct BilingualHeaders: Equatable {
    var time = "Time"
    var thai = "ไทย"
    var latin = "Latin"
    var translit = "Romanization"
}

extension HistoryLogic {
    static func isThaiScript(_ s: String) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let thai = letters.filter { (0x0E01...0x0E5B).contains($0.value) }.count
        return thai * 2 > letters.count
    }

    /// Spalten je Zeile: Thai links, die andere Sprache rechts. Ohne Thai bleibt die Reihenfolge Original | Übersetzung.
    static func bilingualRows(_ s: HistorySession) -> [BilingualRow] {
        s.rows.compactMap { r in
            let a = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let b = r.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            if a.isEmpty && b.isEmpty { return nil }
            let swap = isThaiScript(b) && !isThaiScript(a)
            return BilingualRow(time: r.time, thai: swap ? b : a, latin: swap ? a : b, translit: r.translit)
        }
    }

    private static func clock(_ d: Date, _ tz: TimeZone) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"; df.timeZone = tz; df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: d)
    }

    /// Eine Tabellenzelle: Markdown-Sonderzeichen maskiert, Zeilenumbrüche als <br> (sonst bricht die Tabelle).
    static func mdCell(_ s: String) -> String {
        ExportFormats.mdEscape(s).replacingOccurrences(of: "  \n", with: "<br>")
    }

    /// Markdown-Tabelle: Zeit | Thai | Latein [| Umschrift]. Die Umschrift-Spalte entfällt, wenn nirgends eine vorkommt.
    static func markdownTable(_ s: HistorySession, title: String, headers: BilingualHeaders = BilingualHeaders(),
                              timeZone: TimeZone = .current) -> String {
        let rows = bilingualRows(s)
        let withRoman = rows.contains { !$0.translit.isEmpty }
        var cols = [headers.time, headers.thai, headers.latin] + (withRoman ? [headers.translit] : [])
        var out = "# " + ExportFormats.mdEscape(title) + "\n\n"
        out += "| " + cols.map(mdCell).joined(separator: " | ") + " |\n"
        cols = cols.map { _ in "---" }
        out += "| " + cols.joined(separator: " | ") + " |\n"
        for r in rows {
            var cells = [clock(r.time, timeZone), mdCell(r.thai), mdCell(r.latin)]
            if withRoman { cells.append(mdCell(r.translit)) }
            out += "| " + cells.joined(separator: " | ") + " |\n"
        }
        return out
    }

    static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Eigenständige HTML-Seite für Druck/PDF: zwei Spalten, Thai in einer Thai-Schrift.
    static func htmlTable(_ s: HistorySession, title: String, headers: BilingualHeaders = BilingualHeaders(),
                          timeZone: TimeZone = .current) -> String {
        let rows = bilingualRows(s)
        let withRoman = rows.contains { !$0.translit.isEmpty }
        var out = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>\(htmlEscape(title))</title>\n"
        out += "<style>body{font-family:-apple-system,'Thonburi',sans-serif;font-size:12pt}"
        out += "table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #ccc;padding:4px 8px;vertical-align:top;text-align:left}"
        out += "tr{page-break-inside:avoid}.t{color:#666;white-space:nowrap}.r{color:#666;font-style:italic}</style></head><body>\n"
        out += "<h1>\(htmlEscape(title))</h1>\n<table>\n<tr><th>\(htmlEscape(headers.time))</th><th>\(htmlEscape(headers.thai))</th><th>\(htmlEscape(headers.latin))</th>"
        out += (withRoman ? "<th>\(htmlEscape(headers.translit))</th>" : "") + "</tr>\n"
        for r in rows {
            out += "<tr><td class=\"t\">\(clock(r.time, timeZone))</td><td>\(htmlEscape(r.thai))</td><td>\(htmlEscape(r.latin))</td>"
            out += (withRoman ? "<td class=\"r\">\(htmlEscape(r.translit))</td>" : "") + "</tr>\n"
        }
        return out + "</table>\n</body></html>\n"
    }
}
