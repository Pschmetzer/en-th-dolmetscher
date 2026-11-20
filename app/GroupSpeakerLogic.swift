// GroupSpeakerLogic.swift – Gruppenmodus (Runde 26): Sprecher-Nummern der Engine (`utt.group_speaker`, Name "Sprecher N"),
// Farben, Umbenennen. Reine Logik ohne UI (Tests in swift-tests). Nummern gelten nur bis „Gespräch löschen“ / Engine-Neustart.
import Foundation

enum GroupSpeakerLogic {
    static let paletteSize = 8
    static let maxNameLength = 24

    /// Der Name, den die Engine ohne Stimmprofil vergibt (docs/PROTOKOLL.md, Steuerfeld `group_speakers`).
    static func engineLabel(_ n: Int) -> String { "Sprecher \(n)" }

    /// Gruppen-Nummer, wenn der Sprecher keinem Stimmprofil gehört (Name fehlt oder ist die Engine-Vorgabe); sonst nil.
    static func groupNumber(speaker: String?, group: Int?) -> Int? {
        guard let n = group, n >= 1 else { return nil }
        guard let s = speaker, !s.isEmpty else { return n }
        return s == engineLabel(n) ? n : nil
    }

    /// Palettenplatz 0..<paletteSize (Nummern ab 1; ungültige Werte landen auf 0).
    static func colorIndex(_ n: Int) -> Int { n >= 1 ? (n - 1) % paletteSize : 0 }

    /// Eingabe säubern: Steuerzeichen/Zeilenumbrüche raus, trimmen, höchstens 24 Zeichen; leer = nil (Name entfernen).
    static func sanitize(_ raw: String) -> String? {
        let cleaned = raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        let t = cleaned.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        guard !t.isEmpty else { return nil }
        return String(t.prefix(maxNameLength))
    }

    /// Anzeigename: eigener Name > lokalisierte Vorgabe ("Speaker 2") > Name der Engine.
    static func displayName(speaker: String?, group: Int?, renames: [Int: String],
                            defaultLabel: (Int) -> String = engineLabel) -> String? {
        guard let n = groupNumber(speaker: speaker, group: group) else { return speaker }
        return renames[n] ?? defaultLabel(n)
    }

    /// Alle bisher gesehenen Nummern, aufsteigend (für das Umbenennen-Menü).
    static func numbers(from groups: [Int?]) -> [Int] { Array(Set(groups.compactMap { $0 }.filter { $0 >= 1 })).sorted() }
}
