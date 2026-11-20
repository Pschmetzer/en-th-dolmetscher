// Round34.swift – Runde 34: Logik hinter den Oberflächen, die die Runde-33-Bausteine anbinden (ohne Systemaufrufe, testbar):
// Zeitzone -> Land (Reise-Modus ohne Standortfreigabe), Planer-Speicher (FSRS je Karte), Karten-Themen für Orts-Vorschläge,
// Teiltext-Schalter und -Entscheidung für Whisper, Speisekarten-Auswertung, Hotelkarten-Text aus der Notfallkarte.
import CryptoKit
import Foundation

// MARK: Reise-Modus: Land aus der Zeitzone

/// Das Gerät stellt die Zeitzone beim Reisen selbst um. Das reicht für einen Vorschlag und braucht keine Freigabe.
/// Nur Zeitzonen, die eindeutig auf ein Land zeigen; mehrdeutige (z. B. Europa/Amerika allgemein) liefern nil.
enum TravelRegion {
    static let byZone: [String: String] = [
        "Asia/Bangkok": "TH", "Asia/Tokyo": "JP", "Asia/Seoul": "KR", "Asia/Ho_Chi_Minh": "VN", "Asia/Saigon": "VN",
        "Asia/Jakarta": "ID", "Asia/Makassar": "ID", "Asia/Singapore": "SG", "Asia/Kuala_Lumpur": "MY",
        "Asia/Shanghai": "CN", "Asia/Taipei": "TW", "Europe/Berlin": "DE", "Europe/Vienna": "AT", "Europe/Zurich": "CH",
        "Europe/Madrid": "ES", "Europe/Paris": "FR", "Europe/London": "GB", "Pacific/Auckland": "NZ",
        "Australia/Sydney": "AU", "Australia/Melbourne": "AU", "Australia/Brisbane": "AU", "Australia/Perth": "AU",
        "America/Mexico_City": "MX", "America/New_York": "US", "America/Chicago": "US", "America/Denver": "US",
        "America/Los_Angeles": "US",
    ]

    static func region(forZone id: String) -> String? { byZone[id] }
}

/// Merkt sich, für welches Land der Vorschlag schon abgelehnt oder angenommen wurde (einmal je Land).
enum TravelPrompt {
    static let key = "travelDismissed34"
    static let enabledKey = "travelMode34"

    static func shouldShow(_ s: TravelMode.Suggestion?, dismissed: String?, enabled: Bool) -> Bool {
        guard enabled, let s else { return false }
        return s.region != dismissed?.uppercased()
    }
}

// MARK: Planer (FSRS je Karte)

/// FSRS-Zustand je Karte des Lernkastens. Eigene Ablage: Karteikasten (learn.json) und seine Fächer bleiben unverändert.
struct PlannerStore: Codable, Equatable, Sendable {
    var states: [String: SpacedRepetition.State] = [:]

    static let defaultsKey = "planner34"

    /// Karten aus Gesprächen tragen den Satz in ihrer Kennung. UserDefaults liegt im Backup und ist nicht geschützt:
    /// darum steht dort nur ein Hash, nie der Satz selbst.
    static func key(_ cardID: String) -> String {
        SHA256.hash(data: Data(cardID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Bewertung einer Karte. Unbekannte Karten beginnen neu.
    mutating func rate(_ id: String, _ rating: SpacedRepetition.Rating, now: Date) {
        let k = Self.key(id)
        let old = states[k] ?? SpacedRepetition.fresh(now: now)
        states[k] = SpacedRepetition.review(old, rating, now: now)
    }

    /// Zustände von Karten, die es nicht mehr gibt, verwerfen.
    mutating func prune(keeping ids: Set<String>) {
        let keep = Set(ids.map(Self.key))
        states = states.filter { keep.contains($0.key) }
    }

    /// Alles vergessen (Lernstand zurücksetzen).
    static func clear(_ d: UserDefaults = .standard) { d.removeObject(forKey: defaultsKey) }

    struct Forecast: Equatable {
        var dueNow = 0
        var dueThisWeek = 0
        /// mittlere Abrufchance der bewerteten Karten in Prozent (0 ohne bewertete Karten)
        var recallPercent = 0
        var tracked = 0
    }

    func forecast(now: Date) -> Forecast {
        var f = Forecast()
        var sum = 0.0
        for s in states.values {
            f.tracked += 1
            if SpacedRepetition.isDue(s, now: now) { f.dueNow += 1 }
            else if s.due <= now.addingTimeInterval(7 * 86_400) { f.dueThisWeek += 1 }
            if let last = s.last {
                sum += SpacedRepetition.retrievability(days: now.timeIntervalSince(last) / 86_400, stability: s.stability)
            }
        }
        let reviewed = states.values.filter { $0.last != nil }.count
        f.recallPercent = reviewed == 0 ? 0 : Int((sum / Double(reviewed) * 100).rounded())
        return f
    }

    static func load(_ d: UserDefaults = .standard) -> PlannerStore {
        guard let data = d.data(forKey: defaultsKey), let s = try? JSONDecoder().decode(PlannerStore.self, from: data) else { return PlannerStore() }
        return s
    }

    func save(_ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { d.set(data, forKey: Self.defaultsKey) }
    }
}

/// Themen einer Lernkarte für den Orts-Vorschlag: Kategorie und Paket der Favoriten-Phrase (Karten aus Gesprächen haben keine).
enum CardTopics {
    static func tags(cardID: String, favorites: [Phrase]) -> Set<String> {
        guard cardID.hasPrefix("fav|") else { return [] }
        let key = String(cardID.dropFirst(4))
        guard let p = favorites.first(where: { $0.favoriteKey == key }) else { return [] }
        var t: Set<String> = [p.category.lowercased()]
        if let pack = p.pack?.lowercased() {
            t.insert(pack)
            for part in pack.split(separator: "-") { t.insert(String(part)) }
        }
        return t
    }
}

// MARK: Whisper-Teiltexte

/// Schalter und Entscheidung für Zwischenergebnisse beim Sprechen. Standard aus (mehr Rechenzeit und Akku).
enum WhisperPartials {
    static let key = "whisperPartials34"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }

    static let minSeconds = 1.2
    static let maxSeconds = 24.0
    static let interval = 1.6

    /// Eine Zwischenerkennung nur, wenn: eingeschaltet, mitten in einer Äußerung, lang genug und noch nicht zu lang,
    /// seit der letzten genug Zeit, keine andere Zwischen- oder Enderkennung läuft.
    static func shouldStart(enabled: Bool, inUtterance: Bool, utteranceSeconds: Double, sinceLast: Double,
                            partialBusy: Bool, finalPending: Bool) -> Bool {
        enabled && inUtterance && !partialBusy && !finalPending
            && utteranceSeconds >= minSeconds && utteranceSeconds <= maxSeconds && sinceLast >= interval
    }

    /// Sprache der Vorschau: die zuletzt erkannte, sonst die erste des Paars (keine Spracherkennung für Teiltexte).
    static func language(last: Lang?, langs: [Lang]) -> Lang? {
        if let last, langs.contains(last) { return last }
        return langs.first
    }
}

// MARK: Speisekarte

enum MenuScan {
    /// Allergen-Ids der Notfallkarte. Leer = es gibt nichts zu markieren.
    static func avoidIDs(_ allergens: [Allergen]) -> Set<String> { MenuAllergens.ids(from: allergens) }

    /// Anzeige-Name einer Id in der Oberflächensprache (Weizen und Gluten gehören zur selben Karte).
    static func name(of id: String, in lang: Lang) -> String {
        let a = Allergen(rawValue: id) ?? (id == "wheat" ? .gluten : nil)
        return a?.name(lang) ?? id
    }

    /// Namen ohne Dopplung (Gluten/Weizen), Reihenfolge der Ids.
    static func names(_ ids: [String], in lang: Lang) -> String {
        var seen = Set<String>(), out: [String] = []
        for id in ids {
            let n = name(of: id, in: lang)
            if seen.insert(n).inserted { out.append(n) }
        }
        return out.joined(separator: ", ")
    }

    /// Treffer nach Zeilennummer (für die Markierung in der Liste).
    static func hitsByLine(_ lines: [String], avoid: Set<String>) -> [Int: MenuAllergens.Hit] {
        var out: [Int: MenuAllergens.Hit] = [:]
        let hits = MenuAllergens.scan(lines: lines, avoid: avoid)
        var cursor = 0
        for h in hits {
            // scan liefert Zeilen in Reihenfolge; gleiche Zeilen mehrfach: nächste noch freie Fundstelle
            if let i = lines[cursor...].firstIndex(of: h.line) { out[i] = h; cursor = i + 1 }
        }
        return out
    }
}

// MARK: Hotelkarte aus der Notfallkarte

enum HotelCard {
    /// Erste Zeile = Name, Rest = Adresse (so wird das Feld in der Notfallkarte ausgefüllt).
    static func split(_ hotel: String) -> (name: String, address: String) {
        let lines = hotel.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return ("", "") }
        return (first, lines.dropFirst().joined(separator: ", "))
    }

    enum Outcome: Equatable { case empty, tooLong, ready(String) }

    static func outcome(hotel: String, phone: String) -> Outcome {
        let (n, a) = split(hotel)
        guard !n.isEmpty else { return .empty }
        guard let p = HotelCardQR.payload(name: n, address: a, phone: phone) else { return .tooLong }
        return .ready(p)
    }
}

// MARK: Orts-Vorschläge

enum PlaceChoices {
    /// Orte, die man von Hand wählt (ohne `other`).
    static let all: [PlaceKind] = PlaceKind.allCases.filter { $0 != .other }
    static func textKey(_ p: PlaceKind) -> String { "r34_place_" + p.rawValue }
}
