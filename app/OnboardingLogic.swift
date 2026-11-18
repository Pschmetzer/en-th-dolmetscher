// OnboardingLogic.swift – reine Logik des Erststarts (ohne UI, einzeln testbar): Modellempfehlung nach Hardware,
// Wiederaufnahme nach Abbruch, „Später erinnern“, Handlungsvorschläge bei Fehlern, Stand des Test-Satzes.
import Foundation

enum OnboardingLogic {
    static let remindInterval: TimeInterval = 86_400

    /// Wie `hwprofile.recommend` in der Engine: Intel oder unter 8 GB -> small, Pro/Max/Ultra ab 24 GB -> best, sonst medium.
    static func recommendedModel(ramGB: Double, arm64: Bool, chip: String) -> String {
        if !arm64 || ramGB < 8 { return "small" }
        let c = chip.lowercased()
        let strong = ["pro", "max", "ultra"].contains { c.contains($0) }
        return ramGB >= 24 && strong ? "best" : "medium"
    }

    /// Einrichtung wurde begonnen, aber nie beendet, und es fehlt noch etwas (Umgebung oder Modelle).
    static func interrupted(started: Bool, envMissing: Bool, missingGB: Double?) -> Bool {
        started && (envMissing || (missingGB ?? 0) > 0)
    }

    static func remindDue(until: Double, now: Double) -> Bool { now >= until }

    static func remindUntil(now: Double) -> Double { now + remindInterval }

    /// Schlüssel des Handlungsvorschlags zu einem Fehlerfall von `EnvSetupModel.Phase.failed`.
    static func nextStepKey(kind: String) -> String {
        switch kind {
        case "offline": return "envsetup_next_offline"
        case "disk": return "envsetup_next_disk"
        case "no_space": return "envsetup_next_no_space"
        case "integrity": return "envsetup_next_integrity"
        case "arch": return "envsetup_next_arch"
        case "cancelled": return "envsetup_next_cancelled"
        case "missing_parts": return "envsetup_next_missing_parts"
        default: return "envsetup_next_failed"
        }
    }

    /// Bei Platzmangel kann ein kleineres Modell helfen (nur wenn noch ein größeres gewählt ist).
    static func canShrinkModel(kind: String, model: String) -> Bool {
        (kind == "no_space" || kind == "disk") && model != "small"
    }

    /// Stand des Test-Satzes: mic (Freigabe fehlt) -> start -> say (hört zu) -> done (Satz erkannt).
    static func testPhase(micAuthorized: Bool, listening: Bool, heard: Bool) -> String {
        if heard { return "done" }
        if !micAuthorized { return "mic" }
        return listening ? "say" : "start"
    }
}
