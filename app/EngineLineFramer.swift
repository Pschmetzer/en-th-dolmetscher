// EngineLineFramer.swift – Zeilenpufferung der Engine-Ausgabe (aus Engine.swift herausgelöst, Runde 27, ohne
// Verhaltensänderung): zerlegt Datenblöcke in Zeilen (LF), toleriert CRLF und BOM, verwirft Zeilen über der Grenze.
import Foundation

struct EngineLineFramer {
    /// Eine Zeile über 2 MB ist kein Ereignis (Protokoll-Fehler): verwerfen statt unbegrenzt puffern.
    static let maxLineBytes = 2_000_000

    private(set) var buffer = Data()
    /// Nach einer überlangen Zeile: Rest bis zum nächsten Zeilenende verwerfen (sonst würde das Ende der Zeile als
    /// „Ereignis“ gelesen und zählte als weitere ungültige Zeile).
    private(set) var discarding = false

    struct Output: Equatable {
        var lines: [Data] = []
        /// Größe des verworfenen unvollständigen Puffers, wenn er die Grenze überschritt (zählt als fehlerhafte Zeile).
        var overflowBytes: Int?
    }

    mutating func feed(_ d: Data, limit: Int = EngineLineFramer.maxLineBytes) -> Output {
        var out = Output()
        if discarding {
            guard let nl = d.firstIndex(of: 0x0A) else { return out }
            discarding = false
            buffer.append(d.subdata(in: (nl + 1)..<d.endIndex))
        } else {
            buffer.append(d)
        }
        while let nl = buffer.firstIndex(of: 0x0A) {
            var line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if line.last == 0x0D { line.removeLast() }                       // CRLF tolerieren
            if line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) } // BOM tolerieren
            out.lines.append(line)
        }
        if buffer.count > limit {
            out.overflowBytes = buffer.count
            buffer = Data(); discarding = true
        }
        return out
    }

    mutating func reset() { buffer = Data(); discarding = false }
}
