// Round8.swift – kleine, testbare Bausteine der Runde 8 (Netzwechsel, Lernstatistik, zuletzt gesagte Sätze).
import Foundation
import SwiftUI
import UIKit

/// Lernstatistik: wie viele Karten an welchem Tag beantwortet wurden (nur auf dem Gerät, Teil von learn.json).
struct StudyLog: Codable, Equatable, Sendable {
    /// Tag (`yyyy-MM-dd` im Kalender des Geräts) -> beantwortete Karten.
    var days: [String: Int] = [:]
    /// So viele Tage merkt sich das Protokoll; ältere fallen weg.
    static let keepDays = 400

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    mutating func record(now: Date = Date(), calendar: Calendar = .current) {
        days[Self.key(now, calendar: calendar), default: 0] += 1
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: now) else { return }
        let oldest = Self.key(cutoff, calendar: calendar)
        days = days.filter { $0.key >= oldest }
    }

    func today(now: Date = Date(), calendar: Calendar = .current) -> Int {
        days[Self.key(now, calendar: calendar)] ?? 0
    }

    /// Tage in Folge mit mindestens einer Karte. Heute noch nichts gelernt: die Serie bis gestern zählt weiter.
    func streak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now)
        if today(now: now, calendar: calendar) == 0 {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var n = 0
        while (days[Self.key(day, calendar: calendar)] ?? 0) > 0 {
            n += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }
}

/// Netzwechsel: Sätze, die wegen fehlenden Netzes nicht übersetzt wurden, nach dem Wiederkommen des Netzes nachholen.
enum ReconnectRetry {
    /// Nur Sätze der letzten Minuten (ältere sind nicht mehr Teil des laufenden Gesprächs) und nicht zu viele auf einmal.
    static let window: TimeInterval = 15 * 60
    static let maxCount = 5

    /// Ohne Netz → mit Netz.
    static func cameBack(was: Bool?, now: Bool) -> Bool { was == false && now }

    /// Einträge ohne Übersetzung mit Fehler, älteste zuerst (so bleibt die Reihenfolge des Gesprächs).
    static func pending(_ entries: [Entry], now: Date = Date()) -> [UUID] {
        let open = entries.filter { (e: Entry) -> Bool in
            e.error != nil && e.translation == nil && e.photo != true && !e.text.isEmpty
                && now.timeIntervalSince(e.date) <= window
        }
        return open.suffix(maxCount).map(\.id)
    }
}

extension Phrasebook {
    /// Zuletzt gesagte Satzbuch-Sätze, neueste zuerst, jeder nur einmal. Quelle ist der Verlauf selbst:
    /// Sperre, Aufbewahrung und „Verlauf nicht speichern“ gelten damit automatisch auch hier.
    static func recent(entries: [Entry], in list: [Phrase], limit: Int = 12) -> [Phrase] {
        let byText: [String: Phrase] = Dictionary(list.filter { $0.srcLang == .en }.map { ($0.en, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var out: [Phrase] = []
        for e in entries.reversed() where e.provider == "phrasebook" && e.src == .en {
            guard let p = byText[e.text], seen.insert(p.en).inserted else { continue }
            out.append(p)
            if out.count == limit { break }
        }
        return out
    }
}

extension A11yLabel {
    /// Text, den VoiceOver mit der Stimme der Sprache `lang` liest (statt der Oberflächensprache).
    static func spoken(_ s: String, _ lang: Lang) -> Text {
        text(NSAttributedString(string: s, attributes: [.accessibilitySpeechLanguage: lang.voiceLocale]))
    }
}

// MARK: Zwischenablage

/// Kopieren mit Datenschutz: nur auf diesem Gerät (kein Universal Clipboard) und – wenn gewünscht – nach 2 Minuten gelöscht.
enum SecureCopy {
    static let lifetime: TimeInterval = 120

    static func options(expiring: Bool, now: Date = Date()) -> [UIPasteboard.OptionsKey: Any] {
        var o: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if expiring { o[.expirationDate] = now.addingTimeInterval(lifetime) }
        return o
    }

    @MainActor static func copy(_ text: String, expiring: Bool) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: options(expiring: expiring))
        Haptics.tap()
    }
}

// MARK: Fehler mit Handlungsvorschlag

enum ErrorAdvice {
    enum Action: Equatable { case none, appSettings, systemSettings }

    /// Welcher Knopf gehört zur Fehlermeldung? Verglichen wird in allen Oberflächensprachen
    /// (der Fehlertext steht im Eintrag in der Sprache von damals).
    static func action(for error: String) -> Action {
        func matches(_ key: String) -> Bool { L10n.languages.contains { L10n.text(key, lang: $0) == error } }
        if matches("err_offline_missing") || matches("err_offline_only") { return .appSettings }
        if matches("err_denied") || matches("err_no_mic") { return .systemSettings }
        return .none
    }
}

// MARK: Sichtschutz bei Bildschirmaufnahme

enum ShieldPolicy {
    static func show(shield: Bool, active: Bool, hideOnCapture: Bool, captured: Bool) -> Bool {
        (shield && !active) || (hideOnCapture && captured)
    }

    /// Wird der Bildschirm gerade aufgenommen oder gespiegelt (AirPlay, Bildschirmaufnahme)?
    @MainActor static var isCaptured: Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.contains { $0.screen.isCaptured }
    }
}

// MARK: Satzbuch und Lernen

extension Phrasebook {
    /// Liste als Text zum Teilen: "Satz – Thai (Umschrift)", eine Zeile je Satz.
    static func shareText(_ list: [Phrase], politeness: Politeness) -> String {
        list.map { p in
            let target = p.dstLang == .th ? politeness.fill(p.th) : p.th
            let roman = Phrasebook.roman(p, politeness: politeness).flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
            return "\(p.en) – \(target)\(roman)"
        }.joined(separator: "\n")
    }
}

extension LeitnerDeck {
    /// „Alle jetzt üben“: alle Karten, auch die noch nicht fälligen; niedrige Fächer zuerst.
    func practice() -> [Card] {
        cards.sorted { $0.box != $1.box ? $0.box < $1.box : $0.due < $1.due }
    }

    /// Alles zurück in Fach 1, sofort fällig. Karten und Tagesstatistik bleiben.
    mutating func resetProgress(now: Date = Date()) {
        for i in cards.indices { cards[i].box = 1; cards[i].due = now }
    }
}
