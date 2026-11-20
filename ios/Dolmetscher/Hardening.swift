// Hardening.swift – kleine, getestete Bausteine der Runde 30: Fehlerprotokoll der Audio-Sitzung, Zeitgrenzen, Konstanten.
import AVFoundation
import Foundation
import os

private let log = Logger(subsystem: "dolmetscher", category: "session")

extension AVAudioSession {
    /// Audio-Sitzung umschalten und Fehler protokollieren statt sie mit `try?` zu verschlucken
    /// (Anruf, anderes Gerät hält die Sitzung: sonst fehlt jede Spur, warum nichts zu hören war).
    /// `false`, wenn die Umschaltung scheiterte.
    @discardableResult
    func attempt(_ what: String, _ op: (AVAudioSession) throws -> Void) -> Bool {
        do { try op(self); return true } catch {
            log.error("\(what, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// Zeitgrenzen der Sprachausgabe-Reihe.
enum SpeechTiming {
    /// Längstens so lange auf den Text eines Satzes warten (Übersetzung hängt), dann überspringen – sonst steht die ganze Reihe.
    static let produceTimeout = 15.0
    /// Nachhall nach dem letzten Satz nicht als Sprache werten.
    static let tailMilliseconds = 400
    /// Hinweise wie „Lautstärke niedrig“ oder „Stimme fehlt“ höchstens einmal je Minute.
    static let hintCooldown = 60.0
    /// Fällt ein Erkenner innerhalb dieser Zeit ein zweites Mal aus, gibt es einen Fehler statt Neustart.
    static let recognizerRetryWindow = 60.0
    /// Push-to-talk: so lange darf das Ergebnis nach dem Loslassen brauchen.
    static let pttDrainSeconds = 2.5
}

/// Gemeinsame Zeitgrenzen der Speicherung.
enum StorageLimits {
    /// Gleichzeitig behaltene Sicherungskopien (`.bak-…`, `.corrupt-…`) je Datei.
    static let keepCopies = 3
    /// So lange bleibt Gelöschtes („Verlauf leeren“) zurückholbar.
    static let undoSeconds: TimeInterval = 8
}

/// Fehler, die bewusst nicht an die Oberfläche gehen, aber nicht spurlos verschwinden sollen.
enum Diag {
    static func fail(_ what: String, _ error: Error) {
        log.error("\(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
    static func note(_ message: String) { log.error("\(message, privacy: .public)") }
}

/// Sprachpaket-Download: Abbruch im Systemdialog ist normal, andere Fehler gehören ins Protokoll.
enum PackLog {
    static func failed(_ error: Error) {
        log.error("Sprachpaket-Download: \(error.localizedDescription, privacy: .public)")
    }
}
