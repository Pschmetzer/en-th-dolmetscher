// UtteranceLogic.swift – wohin ein `utt`-Ereignis in der Blasenliste gehört (reine Logik, Foundation; getestet in swift-tests).
import Foundation

/// Minimale Sicht auf eine Blase für die Platzierungsentscheidung.
struct BubbleKey: Equatable {
    var uid: String?
    var pending: Bool
    var speaker: String?
    var text: String
    var out: String
    var date: Date
}

enum UttPlacement: Equatable {
    case replace(Int)   // vorhandene Blase an dieser Position ersetzen (Position bleibt erhalten)
    case append         // neue Blase
}

enum UtteranceLogic {
    /// Zeitfenster, in dem gleicher Text vom gleichen Sprecher als Doppelmeldung gilt.
    static let dedupWindow: TimeInterval = 4.0
    /// So viele letzte Blasen werden fürs inhaltliche Dedup geprüft.
    static let dedupLookback = 6
    /// Platzhalter ohne Ereignis verfallen nach dieser Zeit.
    static let hearingTimeout: TimeInterval = 3.0

    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let kept = lowered.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }
        return String(String.UnicodeScalarView(kept))
    }

    /// Entscheidet, ob ein `utt` eine Blase ersetzt oder neu angehängt wird. Idempotent: dieselbe uid ersetzt immer.
    static func place(in items: [BubbleKey], uid: String?, replaces: String?, text: String, out: String,
                      speaker: String?, now: Date = Date()) -> UttPlacement {
        if let r = replaces, let i = items.lastIndex(where: { $0.uid == r }) { return .replace(i) }
        if let uid {
            if let i = items.lastIndex(where: { $0.pending && $0.uid == uid }) { return .replace(i) }
            if let i = items.lastIndex(where: { $0.uid == uid }) { return .replace(i) }   // zweites `utt` mit gleicher uid
        }
        let n = normalize(text)
        if n.count >= 3 {
            for i in items.indices.suffix(dedupLookback).reversed() {
                let b = items[i]
                guard !b.pending, normalize(b.text) == n else { continue }
                guard now.timeIntervalSince(b.date) <= dedupWindow, now.timeIntervalSince(b.date) >= -1 else { continue }
                if let u = uid, let bu = b.uid, u != bu, normalize(b.out) != normalize(out) { continue }
                let sameSpeaker = b.speaker == speaker || b.speaker == nil || speaker == nil
                if sameSpeaker { return .replace(i) }
            }
        }
        return .append
    }

    /// Soll ein Platzhalter nach Ablauf der Frist entfernt werden? Nicht, wenn der Text schon fertig erkannt ist
    /// (`heard`), die Übersetzung läuft (`thinking`) oder noch jemand spricht.
    static func shouldExpirePlaceholder(heard: Bool, inRecognition: Bool, secondsSinceVoice: TimeInterval) -> Bool {
        !heard && !inRecognition && secondsSinceVoice >= 1.0
    }
}

/// Zähler „neu unten“ für die Schaltfläche „Zum Neuesten“.
struct JumpCounter: Equatable {
    private(set) var unseen = 0
    mutating func newItem(atBottom: Bool) { if atBottom { unseen = 0 } else { unseen += 1 } }
    mutating func reachedBottom() { unseen = 0 }
    var label: String { unseen > 99 ? "99+" : String(unseen) }
}

/// Statuszeile: Fehler überschreibt eine Latenzanzeige nicht und umgekehrt, bis er abläuft.
enum StatusLine {
    static func compose(error: String?, errorAge: TimeInterval, base: String, latency: Double?) -> String {
        if let e = error, errorAge < 30 { return e }
        if let l = latency, base.isEmpty == false { return base + String(format: " · %.1f s", l) }
        return base
    }
}
