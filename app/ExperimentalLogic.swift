// ExperimentalLogic.swift – Runde 26: experimentelle Schalter (welche Steuerfelder die laufende Engine kennt,
// `ready.capabilities`), Aufnahmequelle, Latenz-Verteilung, `mic_gap`, Verlauf-Passwort, `msg_en`.
// Reine Logik ohne UI (Tests in swift-tests).
import Foundation

enum ExperimentalLogic {
    /// Reihenfolge der Anzeige; gleiche Namen wie die Steuerfelder (docs/PROTOKOLL.md, Runde 24).
    static let ids = ["llm_stream", "llm_router", "defer", "parallel_alt", "stt_prompt", "speak_numbers"]

    static func supported(_ id: String, caps: [String]) -> Bool { caps.contains("control:" + id) }

    static func feature(_ name: String, caps: [String]) -> Bool { caps.contains("feature:" + name) }

    /// `ready.capabilities`: nur Strings, keine Duplikate/Leerwerte.
    static func parseCaps(_ any: Any?) -> [String] {
        var seen = Set<String>()
        return (any as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// `state.switches` -> nur bekannte Schalter mit Bool-Wert.
    static func parseSwitches(_ any: Any?) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for (k, v) in (any as? [String: Any] ?? [:]) where ids.contains(k) {
            if let b = v as? Bool { out[k] = b }
        }
        return out
    }

    /// Nach `ready` zu sendende Felder: nur eingeschaltete und von der Engine unterstützte (Standard der Engine ist aus).
    static func controlsAfterReady(enabled: [String: Bool], caps: [String]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for id in ids where enabled[id] == true && supported(id, caps: caps) { out[id] = true }
        return out
    }

    /// Wie viele Schalter sind an.
    static func activeCount(_ enabled: [String: Bool]) -> Int { ids.filter { enabled[$0] == true }.count }
}

/// Quelle der Aufnahme (Steuerfeld/Argument `source`).
enum AudioSourceLogic {
    static let mic = "mic", system = "system"
    static func normalize(_ raw: String?) -> String { raw == system ? system : mic }
    static func launchArgs(_ source: String) -> [String] { normalize(source) == system ? ["--source", system] : [] }
}

/// Latenz-Verteilung über Sitzungen (`state.latency_hist`: {stt|tr|sound: {n, p50, p95}}).
enum LatencyHistLogic {
    struct Row: Equatable { var kind: String; var n: Int; var p50: Double; var p95: Double }
    static let kinds = ["stt", "tr", "sound"]

    static func parse(_ any: Any?) -> [Row] {
        guard let d = any as? [String: Any] else { return [] }
        return kinds.compactMap { k in
            guard let r = d[k] as? [String: Any],
                  let n = (r["n"] as? NSNumber)?.intValue, n > 0,
                  let p50 = (r["p50"] as? NSNumber)?.doubleValue, let p95 = (r["p95"] as? NSNumber)?.doubleValue,
                  p50.isFinite, p95.isFinite, p50 >= 0, p95 >= p50 else { return nil }
            return Row(kind: k, n: n, p50: p50, p95: p95)
        }
    }

    /// Balkenlänge 0...1 relativ zum größten p95 aller Zeilen.
    static func fraction(_ v: Double, rows: [Row]) -> Double {
        let top = rows.map(\.p95).max() ?? 0
        return top > 0 ? min(1, max(0, v / top)) : 0
    }

    static func seconds(_ v: Double) -> String { String(format: "%.1f s", v) }
}

/// Hinweis `mic_gap`: Mikrofon-Puffer lief über, der folgende Satz kann unvollständig sein.
struct MicGapTracker: Equatable {
    var count = 0
    var last: Date?
    static let visibleFor: TimeInterval = 90

    mutating func register(_ now: Date = Date()) { count += 1; last = now }
    mutating func reset() { count = 0; last = nil }
    func visible(_ now: Date = Date()) -> Bool {
        guard let l = last else { return false }
        let age = now.timeIntervalSince(l)
        return age >= 0 && age < Self.visibleFor
    }
}

/// Passwort des verschlüsselten Verlaufs: was in Umgebung und Steuerfeld geht.
enum HistoryPasswordLogic {
    static let envName = "DOLMETSCHER_HISTORY_PASSWORD"
    static let maxLength = 256

    /// Gültig: nicht leer, kein Zeilenumbruch/Steuerzeichen, höchstens 256 Zeichen.
    static func isValid(_ s: String) -> Bool {
        !s.isEmpty && s.count <= maxLength && !s.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Wert für die Umgebung: nur wenn die Verschlüsselung an ist und ein Passwort gespeichert ist.
    static func envValue(enabled: Bool, password: String?) -> String? {
        guard enabled, let p = password, isValid(p) else { return nil }
        return p
    }

    /// Steuerfeld: Passwort oder "" (löscht es in der Engine).
    static func controlValue(enabled: Bool, password: String?) -> String {
        envValue(enabled: enabled, password: password) ?? ""
    }

    /// Die CLI-Aufrufe mit Verlauf (`--history-export`, `--history-clear`, `--history-purge` …) brauchen das Passwort.
    static func needsEnv(args: [String]) -> Bool { args.contains { $0.hasPrefix("--history") } }

    static func apply(to env: inout [String: String], enabled: Bool, password: String?) {
        env[envName] = nil
        if let v = envValue(enabled: enabled, password: password) { env[envName] = v }
    }
}

/// Fehlertext der Engine ohne bekannten Code: englisch, wenn die App nicht deutsch ist und `msg_en` vorliegt.
enum ErrorTextLogic {
    static func fallback(msg: String?, msgEn: String?, german: Bool) -> String? {
        if !german, let e = msgEn, !e.isEmpty { return e }
        return msg
    }
}
