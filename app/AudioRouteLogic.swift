// AudioRouteLogic.swift – Audio-Ausgabe je Richtung (meine Übersetzungen z. B. auf die Kopfhörer, die des Gegenübers auf den
// Lautsprecher). Hier nur Einstellungen und Auflösung; die Engine bekommt die Felder erst, wenn sie die Richtung kennt
// (Protokollfelder `output_device_me` / `output_device_other`, additiv, leer = Standard-Ausgabe). Nur Foundation; getestet.
import Foundation

struct AudioRoute: Equatable {
    var mine = ""       // UID des Ausgabegeräts für Übersetzungen, die ich höre ("" = Standard-Ausgabe)
    var partner = ""    // UID für Übersetzungen, die das Gegenüber hört
}

enum AudioRouteLogic {
    static let mineKey = "audioRouteMine"
    static let partnerKey = "audioRoutePartner"

    /// Eine eigene Richtung ist nur gesetzt, wenn mindestens ein Gerät gewählt ist.
    static func isActive(_ r: AudioRoute) -> Bool { !r.mine.isEmpty || !r.partner.isEmpty }

    /// UID für eine Rolle der Äußerung ("me" / "other" / nil): leere Wahl fällt auf das allgemeine Ausgabegerät zurück.
    static func uid(for role: String?, route r: AudioRoute, fallback: String) -> String {
        let pick = role == "other" ? r.partner : (role == "me" ? r.mine : "")
        return pick.isEmpty ? fallback : pick
    }

    struct Resolution: Equatable {
        var mine: String
        var partner: String
        var missing: [String]   // gewählte, aber nicht angeschlossene Geräte (Hinweis statt stiller Umleitung)
    }

    static func resolve(_ r: AudioRoute, fallback: String, available: [String]) -> Resolution {
        let avail = Set(available)
        var missing: [String] = []
        func pick(_ chosen: String) -> String {
            if chosen.isEmpty { return fallback }
            if avail.contains(chosen) { return chosen }
            missing.append(chosen)
            return fallback
        }
        let mine = pick(r.mine), partner = pick(r.partner)
        return Resolution(mine: mine, partner: partner, missing: missing)
    }

    /// Zusätzliche Steuerfelder für die Engine: nur gesetzte Geräte, sonst leer (die Engine ignoriert Fehlendes).
    static func protocolFields(_ r: AudioRoute) -> [String: String] {
        var f: [String: String] = [:]
        if !r.mine.isEmpty { f["output_device_me"] = r.mine }
        if !r.partner.isEmpty { f["output_device_other"] = r.partner }
        return f
    }

    /// Gleiches Gerät für beide Richtungen ist erlaubt, aber ein Hinweis wert (Echo-Gefahr bei Mikrofon im Raum).
    static func sameDevice(_ r: AudioRoute) -> Bool { !r.mine.isEmpty && r.mine == r.partner }
}
