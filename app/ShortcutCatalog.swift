// ShortcutCatalog.swift – Daten für das Tastaturkürzel-Fenster (suchbar, nach Gruppen), Benachrichtigungs-Aktionen und
// die Nutzlast für Handoff/Kurzbefehle (App Intents). Nur Foundation; getestet in swift-tests.
import Foundation

struct ShortcutEntry: Equatable {
    var keys: String
    var labelKey: String   // L10n-Schlüssel (L.t)
    var group: String      // Gruppenschlüssel: conversation, view, window
}

enum ShortcutCatalog {
    static let all: [ShortcutEntry] = [
        .init(keys: "⌘↩", labelKey: "shortcut_startstop", group: "conversation"),
        .init(keys: "⌘P", labelKey: "pause", group: "conversation"),
        .init(keys: "⌘.", labelKey: "stop_speaking", group: "conversation"),
        .init(keys: "⌘R", labelKey: "replay_last", group: "conversation"),
        .init(keys: "⇧⌘C", labelKey: "copy_last", group: "conversation"),
        .init(keys: "⌘L", labelKey: "focus_typing", group: "conversation"),
        .init(keys: "⌥⌘S", labelKey: "speak_toggle", group: "conversation"),
        .init(keys: "⌥⌘L", labelKey: "direction_cycle", group: "conversation"),
        .init(keys: "⌥⌘K", labelKey: "menu_swap_pair", group: "conversation"),
        .init(keys: "⌘1–⌘9", labelKey: "quick_phrases", group: "conversation"),
        .init(keys: "⌘F", labelKey: "find", group: "view"),
        .init(keys: "⌘+ ⌘- ⌘0", labelKey: "font_bigger", group: "view"),
        .init(keys: "⇧⌘P", labelKey: "partner_view", group: "window"),
        .init(keys: "⌥⌘M", labelKey: "mini_title", group: "window"),
        .init(keys: "⌥⌘T", labelKey: "always_on_top", group: "window"),
        .init(keys: "⇧⌘E", labelKey: "export", group: "window"),
        .init(keys: "⌘/", labelKey: "show_shortcuts", group: "window"),
    ]

    /// Filtert nach Suchtext in Kürzel oder beschrifteter Aktion (`label` löst den Schlüssel auf); leer = alle.
    static func filter(_ entries: [ShortcutEntry], query: String, label: (String) -> String) -> [ShortcutEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.keys.lowercased().contains(q) || label($0.labelKey).lowercased().contains(q) }
    }

    /// Nach Gruppen in fester Reihenfolge; leere Gruppen entfallen.
    static func grouped(_ entries: [ShortcutEntry]) -> [(group: String, entries: [ShortcutEntry])] {
        ["conversation", "view", "window"].compactMap { g in
            let e = entries.filter { $0.group == g }
            return e.isEmpty ? nil : (g, e)
        }
    }

    /// Kürzel, die mehr als einer Aktion zugeordnet sind (Pflege-Check).
    static func duplicates(_ entries: [ShortcutEntry]) -> [String] {
        var seen = Set<String>(), dup = Set<String>()
        for e in entries where !seen.insert(e.keys).inserted { dup.insert(e.keys) }
        return dup.sorted()
    }
}

// MARK: Benachrichtigungen mit Aktionen

enum NoticeKind: Equatable { case engineStopped, summaryReady, scenarioSuggested(String), rateReminder }

struct NoticeAction: Equatable {
    var id: String
    var labelKey: String
    var foreground: Bool
}

enum NoticeLogic {
    /// Aktionen je Benachrichtigung (Kennung → Beschriftung, R24T-Schlüssel); die Kennung kommt beim Klick zurück.
    static func actions(for kind: NoticeKind) -> [NoticeAction] {
        switch kind {
        case .engineStopped: return [NoticeAction(id: "restart", labelKey: "n_restart", foreground: true)]
        case .summaryReady: return [NoticeAction(id: "copy-summary", labelKey: "n_copy", foreground: false),
                                    NoticeAction(id: "open-summary", labelKey: "n_open", foreground: true)]
        case .scenarioSuggested: return [NoticeAction(id: "use-scenario", labelKey: "n_use", foreground: true),
                                         NoticeAction(id: "dismiss-scenario", labelKey: "n_dismiss", foreground: false)]
        case .rateReminder: return [NoticeAction(id: "open-rate", labelKey: "n_open", foreground: true)]
        }
    }

    /// Benachrichtigung nur, wenn die App nicht im Vordergrund ist, und höchstens einmal je `minGap` Sekunden je Art.
    static func shouldDeliver(appActive: Bool, lastDelivered: Date?, now: Date, minGap: TimeInterval = 300) -> Bool {
        guard !appActive else { return false }
        guard let last = lastDelivered else { return true }
        return now.timeIntervalSince(last) >= minGap
    }
}

// MARK: Handoff / Kurzbefehle

/// Zustand, der per Handoff (NSUserActivity) oder Kurzbefehl übergeben wird: nur Text und Sprachen, nie Schlüssel.
struct HandoffPayload: Equatable {
    static let activityType = "de.dolmetscher.conversation"
    var lastText: String
    var lastOut: String
    var from: String
    var to: String

    var userInfo: [String: String] { ["text": lastText, "out": lastOut, "from": from, "to": to] }

    /// Nutzlast aus userInfo; Texte auf 1000 Zeichen begrenzt, Sprachcodes nur a-z/-, sonst nil.
    static func parse(_ info: [AnyHashable: Any]?) -> HandoffPayload? {
        guard let info, let from = info["from"] as? String, let to = info["to"] as? String,
              valid(from), valid(to) else { return nil }
        let cut = { (s: String?) in String((s ?? "").prefix(1000)) }
        return HandoffPayload(lastText: cut(info["text"] as? String), lastOut: cut(info["out"] as? String), from: from, to: to)
    }

    private static func valid(_ c: String) -> Bool {
        (2...8).contains(c.count) && c.allSatisfy { ("a"..."z").contains($0) || $0 == "-" }
    }

    /// `dolmetscher://say?text=…&lang=…` für Kurzbefehle („Satz sagen“). nil bei leerem oder zu langem Text.
    static func sayURL(text: String, lang: String?) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 1000 else { return nil }
        var c = URLComponents()
        c.scheme = "dolmetscher"; c.host = "say"
        c.queryItems = [URLQueryItem(name: "text", value: t)] + (lang.map { valid($0) ? [URLQueryItem(name: "lang", value: $0)] : [] } ?? [])
        return c.url
    }
}
