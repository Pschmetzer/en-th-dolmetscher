// AudioSessionPolicy.swift – reine Entscheidungen zur Audio-Sitzung (Route, Unterbrechung, Leerlauf), ohne AVFoundation.
// AudioCapture und InterpreterModel fragen hier; die Übergänge sind in Round19Tests belegt.
import Foundation

enum RouteReason: Equatable { case oldDeviceUnavailable, newDeviceAvailable, other }

enum RouteAction: Equatable {
    /// Nichts tun (Ausgabe-Gerät kam dazu, Eingang blieb gleich).
    case ignore
    /// Ausgabe-Gerät weg, Mikrofon unverändert: Vorlesen anhalten und Hinweis, die Aufnahme läuft weiter.
    case outputLost
    /// Mikrofon-Gerät weg: Vorlesen anhalten, Hinweis, Aufnahme neu aufbauen.
    case inputLost
    /// Anderes Mikrofon da: Aufnahme neu aufbauen.
    case rebuild
}

enum AudioSessionPolicy {
    /// Ein Neuaufbau ist nur nötig, wenn sich die Eingabegeräte (UIDs) geändert haben; reine Ausgabegeräte
    /// (A2DP-Kopfhörer ohne Mikrofon) kosten sonst einen Neustart samt Modellen und verschlucken den Satz.
    static func routeAction(reason: RouteReason, inputsBefore: [String], inputsAfter: [String]) -> RouteAction {
        let inputChanged = Set(inputsBefore) != Set(inputsAfter)
        switch reason {
        case .oldDeviceUnavailable: return inputChanged ? .inputLost : .outputLost
        case .newDeviceAvailable: return inputChanged ? .rebuild : .ignore
        case .other: return .ignore
        }
    }

    /// Während eines Anrufs hält das System die Audio-Session: ein Neuaufbau scheitert dort und zeigt einen Fehler.
    /// Nach dem Ende der Unterbrechung kommt ohnehin ein eigener Neustart.
    static func mayRebuild(interrupted: Bool) -> Bool { !interrupted }

    /// Leerlauf zählt nicht, solange eine Unterbrechung dauert: nach einem langen Anruf soll die App nicht sofort „Auto-Stopp“ melden.
    static func effectiveIdle(_ idle: Double, interrupted: Bool) -> Double { interrupted ? 0 : idle }
}
