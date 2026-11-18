// GlossaryLogic.swift – reine Glossar-Logik (Parsen, Prüfen, CSV, Vorschau). Nur Foundation, per swiftc getestet.
// Format wie in dolmetscher.py (load_glossary): je Zeile `Wort => Übersetzung` oder nur `Name`; `#` = Kommentar.
import Foundation

struct GlossaryEntry: Equatable {
    var term: String
    var translation: String   // leer = Name bleibt unverändert
    var line: Int             // Zeilenindex im Rohtext (-1 = noch nicht im Text)
}

enum GlossaryIssueKind: Equatable { case duplicate, conflict, tooLong, overLimit }

struct GlossaryIssue: Equatable {
    var kind: GlossaryIssueKind
    var line: Int
}

struct CSVImportResult: Equatable {
    var entries: [GlossaryEntry] = []
    var skipped: [(row: Int, reason: String)] = []
    var fatal: String? = nil
    static func == (a: CSVImportResult, b: CSVImportResult) -> Bool {
        a.entries == b.entries && a.fatal == b.fatal && a.skipped.count == b.skipped.count
    }
}

struct GlossaryMergeResult {
    var text: String
    var added = 0
    var duplicates = 0
    var conflicts = 0
    var rejected = 0
}

struct GlossaryHit: Equatable {
    var term: String
    var result: String        // was in der Übersetzung stehen soll
    var kept: Bool            // true = Name bleibt unverändert
}

enum GlossaryLogic {
    static let termMax = 120            // wie TERM_MAX in dolmetscher.py
    static let entryLimit = 200         // wie GLOSSARY_LIMIT
    static let textMax = 20000          // wie GLOSSARY_MAX
    static let csvMaxBytes = 262_144
    static let csvMaxRows = 1000
    static let formulaStarts: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    // MARK: Parsen

    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    static func entries(_ text: String) -> [GlossaryEntry] {
        var out: [GlossaryEntry] = []
        for (i, raw) in lines(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text).enumerated() {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            let parts = raw.components(separatedBy: "=>")
            let term = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if term.isEmpty { continue }
            let tr = parts.count > 1 ? parts.dropFirst().joined(separator: "=>").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            out.append(GlossaryEntry(term: term, translation: tr, line: i))
        }
        return out
    }

    /// Feld ohne Zeilenumbrüche und ohne „=>“ (würden das Zeilenformat zerstören).
    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "=>", with: " ").components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func line(term: String, translation: String) -> String {
        let a = clean(term), b = clean(translation)
        if a.isEmpty { return "" }
        return b.isEmpty ? a : a + " => " + b
    }

    // MARK: Prüfen

    /// Doppelte (Groß/klein egal; gleiche Übersetzung), widersprüchliche (andere Übersetzung), zu lange und
    /// überzählige Einträge. Die Engine nutzt bei Doppelten den ersten Eintrag, die späteren sind wirkungslos.
    static func issues(_ text: String) -> [GlossaryIssue] {
        var firstTranslation: [String: String] = [:]
        var out: [GlossaryIssue] = []
        var valid = 0
        for e in entries(text) {
            if e.term.count > termMax || e.translation.count > termMax { out.append(.init(kind: .tooLong, line: e.line)); continue }
            let key = e.term.lowercased()
            if let first = firstTranslation[key] {
                out.append(.init(kind: first.lowercased() == e.translation.lowercased() ? .duplicate : .conflict, line: e.line))
                continue
            }
            firstTranslation[key] = e.translation
            valid += 1
            if valid > entryLimit { out.append(.init(kind: .overLimit, line: e.line)) }
        }
        return out
    }

    // MARK: Ändern (am Rohtext, Kommentare und Leerzeilen bleiben)

    static func removing(line index: Int, from text: String) -> String {
        var ls = lines(text)
        guard ls.indices.contains(index) else { return text }
        ls.remove(at: index)
        return ls.joined(separator: "\n")
    }

    static func inserting(_ entry: String, at index: Int, into text: String) -> String {
        var ls = lines(text)
        ls.insert(entry, at: min(max(index, 0), ls.count))
        return ls.joined(separator: "\n")
    }

    static func replacing(line index: Int, term: String, translation: String, in text: String) -> String {
        var ls = lines(text)
        let l = line(term: term, translation: translation)
        guard ls.indices.contains(index), !l.isEmpty else { return text }
        ls[index] = l
        return ls.joined(separator: "\n")
    }

    static func appending(term: String, translation: String, to text: String) -> String {
        let l = line(term: term, translation: translation)
        if l.isEmpty { return text }
        return (text.isEmpty || text.hasSuffix("\n") ? text : text + "\n") + l + "\n"
    }

    /// Einträge, die Suchtext in Wort oder Übersetzung enthalten (Groß/klein und Akzente egal).
    static func filter(_ list: [GlossaryEntry], query: String) -> [GlossaryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return list }
        let o: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return list.filter { $0.term.range(of: q, options: o) != nil || $0.translation.range(of: q, options: o) != nil }
    }

    // MARK: CSV

    static func exportCSV(_ list: [GlossaryEntry]) -> String {
        func cell(_ s: String) -> String {
            var v = s
            if let f = v.first, formulaStarts.contains(f) { v = "'" + v }   // Formelschutz für Excel/Numbers
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = list.map { cell($0.term) + "," + cell($0.translation) }
        return (["term,translation"] + rows).joined(separator: "\r\n") + "\r\n"
    }

    /// RFC-4180-artig: Anführungszeichen, doppelte Anführungszeichen, Zeilenumbrüche in Feldern; Trenner , oder ;.
    static func parseCSVRows(_ text: String) -> [[String]] {
        var s = text
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        let firstLine = s.prefix { $0 != "\n" && $0 != "\r" }
        let delim: Character = firstLine.filter({ $0 == ";" }).count > firstLine.filter({ $0 == "," }).count ? ";" : ","
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, wasQuoted = false
        let chars = Array(s)
        var i = 0
        func endField() { row.append(field); field = ""; wasQuoted = false }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty && !wasQuoted) { rows.append(row) }
            row = []
        }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty { quoted = true; wasQuoted = true }
            else if c == delim { endField() }
            else if c == "\n" || c == "\r" || c == "\r\n" { endRow() }
            else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    static func importCSV(_ data: Data) -> CSVImportResult {
        var res = CSVImportResult()
        if data.count > csvMaxBytes { res.fatal = "size"; return res }
        guard let text = String(data: data, encoding: .utf8) else { res.fatal = "encoding"; return res }
        if text.unicodeScalars.contains(where: { $0.value == 0 }) { res.fatal = "binary"; return res }
        var rows = parseCSVRows(text)
        if rows.count > csvMaxRows + 1 { res.fatal = "rows"; return res }
        if let h = rows.first?.first?.lowercased(), ["term", "word", "wort", "name"].contains(h.trimmingCharacters(in: .whitespaces)),
           rows[0].count > 1 { rows.removeFirst() }
        for (n, r) in rows.enumerated() {
            let rowNo = n + 1
            func unquote(_ s: String) -> String {
                if s.count > 1, s.first == "'", let f = s.dropFirst().first, formulaStarts.contains(f) { return String(s.dropFirst()) }
                return s
            }
            guard r.count <= 2 else { res.skipped.append((rowNo, "columns")); continue }
            let rawT = (r.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawB = (r.count > 1 ? r[1] : "").trimmingCharacters(in: .whitespacesAndNewlines)
            if rawT.isEmpty { res.skipped.append((rowNo, "empty")); continue }
            if let f = rawT.first, formulaStarts.contains(f) { res.skipped.append((rowNo, "formula")); continue }
            if let f = rawB.first, formulaStarts.contains(f) { res.skipped.append((rowNo, "formula")); continue }
            let t = clean(unquote(rawT)), b = clean(unquote(rawB))
            if t.isEmpty { res.skipped.append((rowNo, "empty")); continue }
            if t.hasPrefix("#") { res.skipped.append((rowNo, "comment")); continue }
            if t.count > termMax || b.count > termMax { res.skipped.append((rowNo, "long")); continue }
            if t.unicodeScalars.contains(where: { $0.value < 32 }) || b.unicodeScalars.contains(where: { $0.value < 32 }) {
                res.skipped.append((rowNo, "control")); continue
            }
            res.entries.append(GlossaryEntry(term: t, translation: b, line: -1))
        }
        return res
    }

    /// Importierte Einträge an den Text hängen: Doppelte und Widersprüche zu vorhandenen Einträgen (und
    /// untereinander) werden nicht übernommen und gezählt; Grenzen für Anzahl und Textlänge gelten.
    static func merge(_ imported: [GlossaryEntry], into text: String) -> GlossaryMergeResult {
        var res = GlossaryMergeResult(text: text)
        var known: [String: String] = [:]
        for e in entries(text) where known[e.term.lowercased()] == nil { known[e.term.lowercased()] = e.translation }
        for e in imported {
            let key = e.term.lowercased()
            if let old = known[key] {
                if old.lowercased() == e.translation.lowercased() { res.duplicates += 1 } else { res.conflicts += 1 }
                continue
            }
            let next = appending(term: e.term, translation: e.translation, to: res.text)
            if known.count >= entryLimit || next.count > textMax { res.rejected += 1; continue }
            res.text = next
            known[key] = e.translation
            res.added += 1
        }
        return res
    }

    // MARK: Vorschau „so wird es übersetzt“

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter && c.unicodeScalars.allSatisfy { !(0x0E00...0x0E7F).contains($0.value) } || c.isNumber || c == "_" }

    /// Welche Einträge greifen in `sample`? Lateinische Wörter nur als ganzes Wort, Thai als Teilstring (wie die Engine).
    static func preview(_ list: [GlossaryEntry], sample: String) -> [GlossaryHit] {
        var seen = Set<String>(), out: [GlossaryHit] = []
        let hay = Array(sample.lowercased())
        for e in list {
            let key = e.term.lowercased()
            if seen.contains(key) || e.term.count > termMax { continue }
            seen.insert(key)
            let needle = Array(key)
            if needle.isEmpty || needle.count > hay.count { continue }
            var found = false
            var i = 0
            while i + needle.count <= hay.count && !found {
                if Array(hay[i..<(i + needle.count)]) == needle {
                    let before = i > 0 ? hay[i - 1] : nil, after = i + needle.count < hay.count ? hay[i + needle.count] : nil
                    let okBefore = !isWordChar(needle[0]) || before == nil || !isWordChar(before!)
                    let okAfter = !isWordChar(needle[needle.count - 1]) || after == nil || !isWordChar(after!)
                    found = okBefore && okAfter
                }
                i += 1
            }
            if found { out.append(GlossaryHit(term: e.term, result: e.translation.isEmpty ? e.term : e.translation, kept: e.translation.isEmpty)) }
        }
        return out
    }
}
