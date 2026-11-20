// Round27.swift – Vorschläge nach Tageszeit im Satzbuch und „Satz des Tages“ als lokale Benachrichtigung.
import Foundation
import UserNotifications

/// Welche Szenario-Pakete passen zur Uhrzeit? Nur eine Sortierhilfe: die Pakete bleiben alle erreichbar.
enum ScenarioSuggest {
    static func packIDs(hour: Int) -> [String] {
        switch hour {
        case 5..<10: return ["bakery-cafe", "grab-ride-hailing", "bus-train"]
        case 10..<15: return ["restaurant", "street-food", "market"]
        case 15..<18: return ["shopping", "souvenir-jewelry", "massage"]
        case 18..<22: return ["restaurant", "night-market-bargain", "street-food"]
        default: return ["nightlife", "taxi", "hotel"]
        }
    }

    /// Nur vorhandene Pakete, in der Reihenfolge der Vorschläge.
    static func packs(hour: Int, available: [ScenarioPack]) -> [ScenarioPack] {
        packIDs(hour: hour).compactMap { id in available.first { $0.id == id } }
    }
}

/// Satz des Tages: ein eingebauter Satz je Kalendertag, in fester Reihenfolge (kein Zufall, kein Netz, nichts Persönliches).
enum PhraseOfDay {
    static let notificationPrefix = "phrase-of-day-"
    static let days = 7
    static let hour = 9

    static func index(for date: Date, count: Int, calendar: Calendar = .current) -> Int {
        guard count > 0 else { return 0 }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return ((day % count) + count) % count
    }

    static func phrase(for date: Date, in list: [Phrase] = Phrasebook.builtIn, calendar: Calendar = .current) -> Phrase? {
        list.isEmpty ? nil : list[index(for: date, count: list.count, calendar: calendar)]
    }

    static func identifier(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%@%04d%02d%02d", notificationPrefix, c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Zeitpunkte der nächsten `days` Tage um 9 Uhr, die noch in der Zukunft liegen.
    static func fireDates(from now: Date, calendar: Calendar = .current) -> [Date] {
        (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), at > now else { return nil }
            return at
        }
    }

    /// Plant die nächsten Tage neu (nur lokal, ohne Server). Vorher alte Einträge entfernen.
    static func schedule(politeness: Politeness, title: String, now: Date = Date(), center: UNUserNotificationCenter = .current()) async {
        await cancelAll(center: center)
        for at in fireDates(from: now) {
            guard let p = phrase(for: at) else { continue }
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = "\(p.gloss)\n\(politeness.fill(p.th))"
            c.sound = nil
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            do { try await center.add(UNNotificationRequest(identifier: identifier(for: at), content: c, trigger: trigger)) }
            catch { Diag.fail("Satz des Tages planen", error) }
        }
    }

    static func cancelAll(center: UNUserNotificationCenter = .current()) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) })
    }
}
