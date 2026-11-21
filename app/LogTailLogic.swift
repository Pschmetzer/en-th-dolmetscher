// LogTailLogic.swift – letzte Zeilen des aktuellen Engine-Starts aus dem stderr-Log (aus Engine.logTail herausgelöst,
// Runde 27, ohne Verhaltensänderung). Nur Foundation; getestet.
import Foundation

enum LogTailLogic {
    /// `text`: Dateiende des Logs; ab der letzten Kopfzeile `marker`, ohne PyTorch-MPS-Warnung („experimental“), letzte
    /// `n` Zeilen. Leeres Ergebnis -> nil (Aufrufer zeigt „Log leer“).
    static func tail(_ text: String, marker: String, n: Int) -> String? {
        var s = text
        if let r = s.range(of: marker, options: .backwards) {
            s = String(s[r.upperBound...])
            if let nl = s.firstIndex(of: "\n") { s = String(s[nl...]) }   // Rest der Kopfzeile
        }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("experimental") }   // MPS-Warnung von PyTorch, kein Fehler
            .suffix(n)
        let t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
