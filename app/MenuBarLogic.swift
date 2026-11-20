// MenuBarLogic.swift – reine Logik der Menüleiste und des Dock-Menüs (ohne UI): Zustand -> Symbol, Text, Aktionen.
import Foundation

enum MenuBarStatus: Equatable {
    case error, loading, offline, stopped, paused, listening, speaking
}

struct MenuBarInput: Equatable {
    var hasError = false
    var loading = false
    var offline = false
    var active = false
    var paused = false
    var speaking = false
    var hasLast = false
    var running = false
}

struct MenuBarLive: Equatable {
    var done: Int
    var pending: Int
    var latency: Double?
}

enum MenuBarLogic {
    /// Wichtigstes zuerst: Fehler vor Laden vor Offline vor dem normalen Betrieb.
    static func status(_ i: MenuBarInput) -> MenuBarStatus {
        if i.hasError { return .error }
        if i.loading { return .loading }
        if i.offline { return .offline }
        guard i.active else { return .stopped }
        if i.paused { return .paused }
        return i.speaking ? .speaking : .listening
    }

    /// SF-Symbol je Zustand; jede Variante hat eine eigene Form, nicht nur eine andere Farbe.
    static func symbol(_ s: MenuBarStatus) -> String {
        switch s {
        case .error: return "exclamationmark.triangle"
        case .loading: return "hourglass.circle"
        case .offline: return "wifi.slash"
        case .stopped: return "waveform.circle"
        case .paused: return "pause.circle"
        case .listening: return "mic.circle.fill"
        case .speaking: return "speaker.wave.2.circle.fill"
        }
    }

    /// Schlüssel der Text-Alternative (VoiceOver) in L10n.
    static func labelKey(_ s: MenuBarStatus) -> String {
        switch s {
        case .error: return "menu_state_problem"
        case .loading: return "menu_state_loading"
        case .offline: return "menu_state_offline"
        case .stopped: return "stopped"
        case .paused: return "state_paused"
        case .listening: return "state_listening"
        case .speaking: return "menu_state_speaking"
        }
    }

    /// Start/Stopp ist nur bei fertiger Engine sinnvoll; beim Laden wartet der Knopf.
    static func canToggle(_ s: MenuBarStatus) -> Bool { s != .loading }

    static func canPause(_ i: MenuBarInput) -> Bool { i.running && i.active }

    static func canCopyLast(_ i: MenuBarInput) -> Bool { i.hasLast }

    /// Nächster Wert beim Tauschen des Sprachpaars: meine und Partnersprache vertauscht.
    static func swapped(mine: String, partner: String) -> (mine: String, partner: String) {
        (partner, mine)
    }

    /// Live-Zeile im Menüleisten-Extra: Median der letzten bis zu 5 Latenzen (Sekunden); nil ohne Messung.
    static func live(done: Int, pending: Int, latencies: [Double]) -> MenuBarLive {
        let recent = latencies.suffix(5).filter { $0 >= 0 && $0.isFinite }.sorted()
        let med: Double? = recent.isEmpty ? nil
            : (recent.count % 2 == 1 ? recent[recent.count / 2] : (recent[recent.count / 2 - 1] + recent[recent.count / 2]) / 2)
        return MenuBarLive(done: max(0, done), pending: max(0, pending), latency: med)
    }

    /// Nur sinnvoll, solange etwas gesprochen wurde oder wartet.
    static func hasLive(_ l: MenuBarLive) -> Bool { l.done > 0 || l.pending > 0 }

    /// Eintrag in der Popover-Zeile: gekürzter letzter Satz, einzeilig.
    static func preview(_ text: String, limit: Int = 60) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)) + "…"
    }
}
