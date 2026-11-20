// Tuning.swift – reine, getestete Entscheidungen und Konstanten rund um Erkennung, Audio-Sitzung und Übersetzung
// (Runde 31). Keine UI, keine WhisperKit-Typen: Engine, Capture, Translator und Model rufen nur hierher.
import Foundation

/// Akku-/Thermik-Stufe: bestimmt, wie viel Rechenaufwand Whisper je Äußerung treiben darf.
enum PowerProfile: Int, Comparable, Sendable {
    case full, reduced, minimal

    static func < (a: PowerProfile, b: PowerProfile) -> Bool { a.rawValue < b.rawValue }

    static func from(lowPower: Bool, thermal: ProcessInfo.ThermalState) -> PowerProfile {
        switch thermal {
        case .critical: return .minimal
        case .serious: return lowPower ? .minimal : .reduced
        default: return lowPower ? .reduced : .full
        }
    }

    static var current: PowerProfile {
        from(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, thermal: ProcessInfo.processInfo.thermalState)
    }
}

/// Whisper-Parameter je Stufe und Äußerung.
enum WhisperTuning {
    /// Wiederholungen mit höherer Temperatur bei schlechtem Ergebnis (jede kostet eine volle Dekodierung).
    static func fallbackCount(_ p: PowerProfile) -> Int {
        switch p { case .full: return 3; case .reduced: return 1; case .minimal: return 0 }
    }

    /// Zeitbudget einer Erkennung: ein Vielfaches der Audiolänge, mindestens `minBudget`, höchstens `maxBudget`.
    /// Ohne Grenze blockiert eine hängende Dekodierung alle folgenden Äußerungen.
    static let minBudget = 6.0, maxBudget = 60.0

    static func timeBudget(duration: Double, _ p: PowerProfile) -> Double {
        let factor: Double
        switch p { case .full: factor = 3; case .reduced: factor = 2; case .minimal: factor = 1.5 }
        return min(maxBudget, max(minBudget, duration * factor))
    }

    /// Wartende Äußerungen, bevor die ältesten verworfen werden (heiß/Sparmodus: kürzere Schlange).
    static func maxQueuedJobs(_ p: PowerProfile) -> Int { p == .minimal ? 1 : 2 }

    /// Kürzer als das ist ein Klick/Husten, kein Satz – gar nicht erst dekodieren (spart Akku, vermeidet Halluzinationen).
    static let minDecodeSeconds = 0.25
    static let silentRMS: Float = 0.002

    static func shouldDecode(duration: Double, rms: Float) -> Bool {
        duration >= minDecodeSeconds && rms >= silentRMS
    }

    /// Vokabular als Prompt (Namen, Fachwörter): eindeutig, getrimmt, höchstens `maxChars` Zeichen, nur ganze Wörter.
    static let maxPromptChars = 160

    static func promptText(vocabulary: [String], maxChars: Int = maxPromptChars) -> String? {
        var seen = Set<String>()
        var out = ""
        for w in vocabulary {
            let t = w.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            let next = out.isEmpty ? t : out + ", " + t
            if next.count > maxChars { break }
            out = next
        }
        return out.isEmpty ? nil : out
    }

    /// Vokabular für den Prompt; das Modell setzt es (Gesprächsnamen, Glossar). Nur lesen auf der Worker-Task.
    nonisolated(unsafe) static var vocabulary: [String] = []

    /// Aufwärm-Dekodierung nach frischem Laden (Core ML kompiliert sonst beim ersten echten Satz): nur bei voller Leistung.
    static let warmUpSamples = 8_000   // 0,5 s Stille bei 16 kHz

    static func shouldWarmUp(freshlyLoaded: Bool, _ p: PowerProfile) -> Bool { freshlyLoaded && p == .full }
}

/// Pausenschwelle passt sich dem Sprechtempo an: kurze Äußerungen (Zurufe, Ja/Nein) enden früher,
/// lange, überlegte Sätze bekommen mehr Luft.
enum AdaptivePause {
    static let minPause = 0.5, maxPause = 1.6
    static let shortUtterance = 1.0, longUtterance = 8.0
    static let shortFactor = 0.8, longFactor = 1.25

    static func pause(base: Double, lastUtterance: Double?) -> Double {
        guard let d = lastUtterance, d > 0 else { return clamp(base) }
        if d < shortUtterance { return clamp(base * shortFactor) }
        if d > longUtterance { return clamp(base * longFactor) }
        return clamp(base)
    }

    private static func clamp(_ p: Double) -> Double { min(maxPause, max(minPause, p)) }
}

/// Eine knappe Spracherkennung bleibt bei der vorigen Sprache, wenn die Wahrscheinlichkeiten fast gleichauf liegen
/// (Thai/Englisch im selben Gespräch kippt sonst bei kurzen Wörtern hin und her).
enum LangStickiness {
    static let margin: Float = 0.1

    static func choose(probs: [String: Float], langs: [Lang], previous: Lang?) -> Lang? {
        guard let best = WhisperLang.choose(probs: probs, langs: langs) else { return nil }
        guard let prev = previous, prev != best, langs.contains(prev),
              let pBest = probs[best.rawValue], let pPrev = probs[prev.rawValue] else { return best }
        return abs(pBest - pPrev) < margin ? prev : best
    }
}

// MARK: Audio-Sitzung

enum SessionTuning {
    /// `setCategory` nur, wenn sich wirklich etwas ändert: jeder Aufruf kann eine Route-Änderung auslösen und
    /// kostet bei Bluetooth Zeit (Neuaushandlung des Profils).
    static func needsCategory(currentCategory: String, currentOptionsRaw: UInt,
                              wantCategory: String, wantOptionsRaw: UInt) -> Bool {
        currentCategory != wantCategory || currentOptionsRaw != wantOptionsRaw
    }

    /// Bluetooth-HFP liefert nur 8–16 kHz Mono: Whisper versteht darüber deutlich schlechter.
    static let narrowbandRate = 16_000.0

    static func isNarrowband(isHFP: Bool, sampleRate: Double) -> Bool {
        isHFP && sampleRate > 0 && sampleRate <= narrowbandRate
    }

    /// Hinweistext in der Oberflächensprache (Tabelle `round33`, Rückfall Englisch).
    static func warnText(lang: String) -> String {
        L10n.text("r33_hfp_warn", lang: lang) ?? L10n.text("r33_hfp_warn", lang: "en") ?? ""
    }
}

/// Vibrationen drosseln: viele Ereignisse dicht hintereinander (Pegel, Treffer) wären ein Dauerbrummen.
struct HapticThrottle: Sendable {
    var minInterval: TimeInterval = 0.12
    private(set) var last: Date = .distantPast

    mutating func allow(at now: Date) -> Bool {
        guard now.timeIntervalSince(last) >= minInterval else { return false }
        last = now
        return true
    }
}

// MARK: Modell-Konstanten (vorher Zahlen im Code)

enum ModelTuning {
    static let defaultPause = 0.8
    static let defaultAutoStopMinutes = 10
    static let defaultHistoryDays = 30
    static let volumeStep = 0.25
    static let minVolume = 0.25
    static let expectationSeconds = 20.0
    static let wakeSeconds = 6.0
    static let overrideRetrySeconds = 3.0
    static let overrideMaxRetries = 10
    static let finishingGraceSeconds = 3.0
    static let transcriptTail = 300

    /// „Lauter/Leiser“ per Sprachbefehl.
    static func louder(_ v: Double) -> Double { min(1, v + volumeStep) }
    static func quieter(_ v: Double) -> Double { max(minVolume, v - volumeStep) }

    /// Neuer Versuch, den Erkenner-Wechsel zurückzunehmen – solange noch Versuche übrig sind und etwas läuft.
    static func shouldRetryRelease(busy: Bool, attempt: Int) -> Bool { busy && attempt < overrideMaxRetries }

    /// Hinweis „Online-Pause“: Sekunden bis zur nächsten Anfrage, mindestens 1.
    static func cooldownLabel(_ base: String, remaining: TimeInterval) -> String {
        remaining > 0 ? base + " (\(Int(remaining.rounded(.up))) s)" : base
    }
}
