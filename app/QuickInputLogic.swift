// QuickInputLogic.swift – reine Logik für Zwischenablage-Übersetzung und Wiedergabe-Lautstärke. Nur Foundation, per XCTest getestet.
import Foundation

enum ClipboardLogic {
    /// Obergrenze wie beim Eingabefeld (Engine nimmt höchstens 1000 Zeichen je Satz).
    static let maxChars = 1000

    /// Zwischenablage-Text für die Übersetzung aufbereiten: Zeilenumbrüche und Mehrfach-Leerraum zu einem
    /// Leerzeichen, gekürzt auf `limit` Zeichen (an der letzten Wortgrenze, wenn eine in der hinteren Hälfte liegt).
    /// nil bei leerem Text oder reinem Leerraum.
    static func prepare(_ raw: String?, limit: Int = maxChars) -> String? {
        guard let raw else { return nil }
        let flat = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        guard flat.count > limit else { return flat }
        let cut = String(flat.prefix(limit))
        if let sp = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: sp) > limit / 2 {
            return String(cut[..<sp])
        }
        return cut
    }

    /// true, wenn der Text gekürzt werden musste (für den Hinweis „gekürzt“).
    static func wasTruncated(_ raw: String?, limit: Int = maxChars) -> Bool {
        guard let p = prepare(raw, limit: .max) else { return false }
        return p.count > limit
    }
}

enum VolumeLogic {
    /// Wiedergabe-Lautstärke der macOS-Ersatzstimme: AVSpeechUtterance kennt nur 0…1 (Einstellung geht bis 2,0
    /// für die Neural-Stimme der Engine). Nie ganz stumm (min. 0,1), nie über 1.
    static func systemVoice(_ setting: Double) -> Float {
        guard setting.isFinite else { return 1 }
        return Float(min(1, max(0.1, setting)))
    }

    /// Gilt die Einstellung für die Ersatzstimme nur eingeschränkt (über 100 %)?
    static func exceedsSystemVoice(_ setting: Double) -> Bool { setting.isFinite && setting > 1.0001 }
}
