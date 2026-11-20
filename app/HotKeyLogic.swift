// HotKeyLogic.swift – reine Logik für konfigurierbare globale Tastenkürzel (⌃⌥ + Buchstabe). Nur Foundation, per XCTest getestet.
import Foundation

enum HotKeyLogic {
    struct Action: Equatable {
        let id: Int                 // Carbon-Kennung (wie bisher: 1 Start/Stopp, 2 Pause, 3 Push-to-Talk, 4 Stopp, 5 Wiederholen, 6 Zwischenablage)
        let defaultLetter: Character
        let labelKey: String        // L10n-Schlüssel der Beschriftung
    }

    static let actions: [Action] = [
        Action(id: 1, defaultLetter: "D", labelKey: "hk_startstop"),
        Action(id: 2, defaultLetter: "P", labelKey: "pause"),
        Action(id: 4, defaultLetter: "S", labelKey: "stop_speaking"),
        Action(id: 5, defaultLetter: "R", labelKey: "replay_last"),
        Action(id: 6, defaultLetter: "C", labelKey: "translate_clipboard"),
        Action(id: 3, defaultLetter: "T", labelKey: "hold_to_talk"),
    ]

    /// UserDefaults-Schlüssel: Wörterbuch Aktions-ID (als Text) → Buchstabe.
    static let storageKey = "hotkeyLetters"

    /// macOS-Tastencodes (ANSI-Layout, wie kVK_ANSI_*), nur Buchstaben.
    static let keyCodes: [Character: Int] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13,
        "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35, "L": 37, "J": 38, "K": 40,
        "N": 45, "M": 46,
    ]

    static let letters: [Character] = keyCodes.keys.sorted()

    static func keyCode(_ letter: Character) -> Int? { keyCodes[Character(letter.uppercased())] }

    /// Anzeige, z. B. „⌃⌥D“.
    static func display(_ letter: Character) -> String { "⌃⌥" + String(letter).uppercased() }

    /// Gespeicherte Wahl prüfen: nur bekannte Buchstaben, jeder höchstens einmal. Ungültiges oder doppeltes fällt auf
    /// den Standard zurück; ist auch der vergeben, auf den ersten freien Buchstaben. Ergebnis: für jede Aktion genau ein
    /// eindeutiger Buchstabe.
    static func resolve(_ stored: [String: String]) -> [Int: Character] {
        var out: [Int: Character] = [:]
        var used = Set<Character>()
        func free() -> Character { letters.first { !used.contains($0) } ?? "A" }
        for a in actions {
            var pick: Character = a.defaultLetter
            if let s = stored[String(a.id)]?.uppercased(), s.count == 1, let c = s.first, keyCodes[c] != nil, !used.contains(c) {
                pick = c
            } else if used.contains(a.defaultLetter) {
                pick = free()
            }
            if used.contains(pick) { pick = free() }
            used.insert(pick)
            out[a.id] = pick
        }
        return out
    }

    /// Aktuelle Wahl aus UserDefaults.
    static func configured(_ ud: UserDefaults = .standard) -> [Int: Character] {
        resolve(ud.dictionary(forKey: storageKey) as? [String: String] ?? [:])
    }

    /// Neue Wahl für eine Aktion; nil, wenn der Buchstabe ungültig oder schon einer anderen Aktion zugeordnet ist.
    static func assigned(_ letter: Character, to id: Int, current: [Int: Character]) -> [Int: Character]? {
        let c = Character(letter.uppercased())
        guard keyCodes[c] != nil, actions.contains(where: { $0.id == id }) else { return nil }
        if current.contains(where: { $0.key != id && $0.value == c }) { return nil }
        var n = current; n[id] = c
        return n
    }

    /// Als Wörterbuch für UserDefaults.
    static func serialized(_ m: [Int: Character]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: m.map { (String($0.key), String($0.value)) })
    }
}
