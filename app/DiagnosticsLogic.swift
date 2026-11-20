// DiagnosticsLogic.swift – reine Logik für Selbsttest und Diagnosebericht (nur Foundation, per swiftc getestet).
// Schwärzung: Home-Pfad, Nutzername, API-Schlüssel und Tokens kommen nie in den Bericht.
import Foundation

enum DiagnosticsLogic {
    enum Status: String, Hashable { case ok, warn, fail }
    struct Row: Equatable { let id: String; let status: Status; let detail: String }

    /// Reihenfolge der Selbsttest-Zeilen. Schlüssel stehen ausgeschrieben da (tests/test_l10n_keys.py findet sie so).
    static let rowIDs = ["mic", "speaker", "network", "models", "python"]
    static let titleKeys = ["mic": "diag_row_mic", "speaker": "diag_row_speaker", "network": "diag_row_network",
                            "models": "diag_row_models", "python": "diag_row_python"]
    static let fixKeys = ["mic/warn": "diag_fix_mic_warn", "mic/fail": "diag_fix_mic_fail",
                          "speaker/warn": "diag_fix_speaker_warn", "speaker/fail": "diag_fix_speaker_fail",
                          "network/fail": "diag_fix_network_fail", "models/fail": "diag_fix_models_fail",
                          "python/fail": "diag_fix_python_fail"]
    static let overallKeys = [Status.ok: "selftest_ok", .warn: "selftest_warn", .fail: "selftest_fail"]
    static let helpURL = "https://github.com/Pschmetzer/en-th-dolmetscher/blob/main/docs/FEHLERHILFE.md"

    static func suggestionKey(id: String, status: Status) -> String? { fixKeys["\(id)/\(status.rawValue)"] }

    static func overall(_ rows: [Row]) -> Status {
        if rows.contains(where: { $0.status == .fail }) { return .fail }
        return rows.contains(where: { $0.status == .warn }) ? .warn : .ok
    }

    private static let secretPatterns = [
        #"(?i)bearer\s+[A-Za-z0-9._\-]{8,}"#,
        #"(?i)(api[_-]?key|token|secret|password|passwort)\s*[=:]\s*\S+"#,
        #"\bsk-[A-Za-z0-9_\-]{8,}"#,
        #"\b(?:AIza|hf_|ghp_|xox[a-z]-)[A-Za-z0-9_\-]{8,}"#,
        #"[A-Za-z0-9_\-]{40,}"#,
    ]

    static func redact(_ s: String, home: String, user: String) -> String {
        var t = s
        if home.count > 1 { t = t.replacingOccurrences(of: home, with: "~") }
        t = replace(t, pattern: #"/Users/[^/\s"']+"#, with: "~")
        for p in secretPatterns { t = replace(t, pattern: p, with: "<geschwärzt>") }
        if user.count >= 2 { t = t.replacingOccurrences(of: user, with: "<user>", options: .caseInsensitive) }
        return t
    }

    private static func replace(_ s: String, pattern: String, with r: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: r)
    }

    /// Fertiger Bericht: Kopfzeilen, Selbsttest-Ergebnis, letzter Fehler; alles geschwärzt. Keine Gesprächstexte.
    static func report(lines: [String], rows: [Row], lastError: String?, home: String, user: String) -> String {
        var out = lines
        if !rows.isEmpty {
            out.append("Self-test: " + overall(rows).rawValue)
            for r in rows { out.append("  [\(r.status.rawValue)] \(r.id): \(r.detail)") }
        }
        if let e = lastError, !e.isEmpty { out.append("Last error: " + e) }
        return redact(out.joined(separator: "\n"), home: home, user: user) + "\n"
    }
}
