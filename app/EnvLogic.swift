// EnvLogic.swift – reine Logik der Python-Umgebung (nur Foundation, ohne UI): Stempel, Python-Auswahl,
// Ausgabe von setup-env.sh, Platzbedarf. Unit-Tests: tests/test_env_logic_swift.py übersetzt diese Datei
// mit einem Test-Hauptprogramm.
import Foundation

enum EnvLogic {
    /// Name der Stempeldatei in der venv (setup-env.sh schreibt sie als Letztes).
    static let stampName = ".dolmetscher-stamp"

    /// Stempel normalisieren: Zeilen ohne Leerraum am Rand, leere Zeilen weg (CRLF/Zeilenende egal).
    static func normalized(_ s: String?) -> String? {
        guard let s else { return nil }
        let lines = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Die Umgebung passt zur App, wenn der Stempel in der venv exakt dem im Bundle entspricht
    /// (gleicher Lock-Hash, gleiche Python-Version, gleiche Architektur). Fehlt einer: nicht eingerichtet.
    static func stampMatches(expected: String?, actual: String?) -> Bool {
        guard let e = normalized(expected), let a = normalized(actual) else { return false }
        return e == a
    }

    /// Woher das Engine-Python kommt.
    enum PythonSource: Equatable {
        case override(String)   // DOLMETSCHER_PYTHON (Umgebung) bzw. Einstellung DolmetscherPython – Entwickler
        case venv(String)       // eigene venv mit passendem Stempel
        case none               // Einrichtung nötig (nie /usr/bin/python3 starten)
    }

    /// Reihenfolge: Dev-Override → eigene venv (nur mit passendem Stempel) → keins (Einrichtungs-Bildschirm).
    /// Ein gesetzter, aber nicht ausführbarer Override fällt auf die venv zurück.
    static func resolvePython(override: String?, venvPython: String, stampOK: Bool,
                              isExecutable: (String) -> Bool) -> PythonSource {
        if let o = override?.trimmingCharacters(in: .whitespaces), !o.isEmpty {
            let path = (o as NSString).expandingTildeInPath
            if isExecutable(path) { return .override(path) }
        }
        if stampOK && isExecutable(venvPython) { return .venv(venvPython) }
        return .none
    }

    /// Eine Zeile von setup-env.sh.
    enum SetupEvent: Equatable {
        case step(String)       // python | packages | verify
        case done
        case fail(String)       // offline | disk | arch | cancelled | failed
    }

    static func parseSetupLine(_ line: String) -> SetupEvent? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t == "done" { return .done }
        let parts = t.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "step": return .step(parts[1])
        case "fail": return .fail(parts[1])
        default: return nil
        }
    }

    /// Schritt -> Anteil am Fortschrittsbalken der Umgebung (Pakete sind der große Teil).
    static func stepFraction(_ step: String) -> Double {
        switch step {
        case "python": return 0.05
        case "packages": return 0.15
        case "verify": return 0.9
        default: return 0
        }
    }

    /// Platzbedarf der Einrichtung in GB: Python + Pakete (~0,45 GB, der Download-Cache wird danach
    /// gelöscht, liegt währenddessen aber zusätzlich auf der Platte) plus fehlende Modelle, plus 10 % Reserve.
    static let envGB = 0.45
    static let envPeakGB = 0.9
    static func requiredGB(envMissing: Bool, modelsGB: Double) -> Double {
        ((envMissing ? envPeakGB : 0) + max(0, modelsGB)) * 1.1
    }

    /// true, wenn genug frei ist (freeBytes nil = unbekannt: nicht blockieren).
    static func enoughSpace(freeBytes: Int64?, requiredGB: Double) -> Bool {
        guard let freeBytes else { return true }
        return Double(freeBytes) >= requiredGB * 1e9
    }

    /// Fortschritt eines Modell-Downloads (download_progress) als 0…1; nil, wenn die Gesamtgröße fehlt.
    static func downloadFraction(done: Int, total: Int?) -> Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, Double(done) / Double(total)))
    }
}
