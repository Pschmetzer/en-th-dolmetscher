// Round33.swift – testbare Logik der Runde 33 (Reise-Features): stabile Teiltexte, Speisekarten-Allergene, Reise-Modus,
// Zwei-Geräte-Nachrichten, Aussprache-Coach, Wiederholungs-Planer, Standort-Auslöser, Tagebuch, Hotelkarte (QR-Text),
// Uhr-Nachrichten, Spotlight-Plan, Bereitschafts-Ampel, Datei-Schutz, Umweg-Beschriftung. Keine Oberfläche, keine Systemaufrufe
// (die dünnen Hüllen dafür stehen in Round33Platform.swift).
import Foundation

// MARK: Streaming-Teiltexte (Whisper)

/// Zeigt von mehreren aufeinanderfolgenden Zwischenergebnissen nur den Teil, der in den letzten `window` Durchläufen gleich blieb.
/// So flackert nichts, und ein einzelner Ausreißer (Halluzination) erscheint nie. Das Endergebnis ersetzt den Teiltext immer.
struct PartialStabilizer: Sendable {
    var window = 2
    private(set) var history: [String] = []
    private(set) var shown = ""

    /// Neuer Zwischentext (`duration` in Sekunden Ton). Rückgabe: stabiler Teil, nur wenn er länger geworden ist, sonst nil.
    mutating func feed(_ raw: String, duration: Double, rms: Float = 0.05) -> String? {
        guard let clean = Hallucination.clean(raw, duration: duration, rms: rms, compressionRatios: []) else { return nil }
        history.append(clean)
        if history.count > window { history.removeFirst(history.count - window) }
        guard history.count >= window else { return nil }
        let stable = Self.commonPrefix(history)
        guard stable.count > shown.count, stable.hasPrefix(shown) else { return nil }
        shown = stable
        return stable
    }

    /// Das Endergebnis gilt immer; der Zustand beginnt neu.
    mutating func finish(_ final: String) -> String {
        history.removeAll(); shown = ""
        return final
    }

    /// Gemeinsamer Anfang, bei Leerzeichen-Sprachen an der Wortgrenze abgeschnitten.
    static func commonPrefix(_ texts: [String]) -> String {
        guard var p = texts.first else { return "" }
        for t in texts.dropFirst() {
            var out = ""
            for (a, b) in zip(p, t) { if a == b { out.append(a) } else { break } }
            p = out
        }
        // Thai/CJK ohne Leerzeichen: Zeichengrenze genügt. Sonst nur an einer Wortgrenze abschneiden.
        if let last = p.unicodeScalars.last, last.value >= 0x0E00 { return p }
        if texts.allSatisfy({ $0 == p || $0.dropFirst(p.count).first == " " }) { return p }
        guard let cut = p.lastIndex(of: " ") else { return "" }
        return String(p[..<cut]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: Speisekarten-Allergene

/// Findet in erkannten Speisekarten-Zeilen Zutaten, die zu den Allergien des Nutzers passen (Ids wie in allergens.json).
enum MenuAllergens {
    struct Hit: Equatable, Sendable {
        var line: String
        /// sicher erkannt
        var ids: [String]
        /// möglich (z. B. nur „ถั่ว“ = Bohne/Nuss, Art unklar)
        var maybe: [String]
    }

    /// Lateinische Stichwörter: genaues Wort (Plural-s erlaubt); ab 6 Zeichen auch als Wortanfang (Komposita: „Erdnussbutter“).
    private static let latin: [String: [String]] = [
        "egg": ["egg", "ei", "eier", "eigelb", "huevo", "oeuf", "œuf", "mayonnaise", "mayo", "mayonesa"],
        "milk": ["milk", "milch", "cheese", "käse", "butter", "cream", "sahne", "yogurt", "yoghurt", "joghurt", "lait", "leche", "fromage"],
        "wheat": ["wheat", "weizen", "flour", "mehl", "bread", "brot", "noodles", "nudeln", "blé", "trigo"],
        "gluten": ["gluten", "seitan", "barley", "gerste", "rye", "roggen"],
        "soy": ["soy", "soya", "soja", "tofu", "tempeh", "edamame", "miso"],
        "sesame": ["sesame", "sesam", "tahini"],
        "peanut": ["peanut", "erdnuss", "erdnüsse", "cacahuete", "arachide", "groundnut"],
        "treenut": ["cashew", "almond", "mandel", "walnut", "walnuss", "pistachio", "pistazie", "hazelnut", "haselnuss", "pecan"],
        "fish": ["fish", "fisch", "salmon", "lachs", "tuna", "thunfisch", "anchovy", "anchovies", "sardine", "pescado", "poisson", "cod", "mackerel"],
        "shellfish": ["shrimp", "prawn", "prawns", "crab", "krabbe", "lobster", "hummer", "garnele", "garnelen", "crevette", "gambas", "langoustine"],
        "mollusc": ["squid", "oyster", "mussel", "mussels", "clam", "clams", "scallop", "tintenfisch", "auster", "muschel", "octopus", "calamari"],
        "fishsauce": ["fishsauce", "nam pla", "nampla"],
        "shrimppaste": ["kapi", "belacan", "shrimppaste"],
        "msg": ["msg", "glutamat", "glutamate"],
        "mushroom": ["mushroom", "pilz", "pilze", "champignon", "shiitake"],
        "coconut": ["coconut", "kokos", "kokosnuss"],
    ]

    /// Thai: Teilzeichenfolge, mit Ausnahmen für bekannte Fehlgriffe.
    private static let thai: [String: [String]] = [
        "egg": ["ไข่"],
        "milk": ["นม", "ชีส", "เนย", "ครีม", "โยเกิร์ต"],
        "wheat": ["แป้งสาลี", "ขนมปัง", "บะหมี่", "ก๋วยเตี๋ยวเส้นเล็ก"],
        "gluten": ["กลูเตน"],
        "soy": ["ถั่วเหลือง", "เต้าหู้", "ซีอิ๊ว", "เต้าเจี้ยว", "มิโสะ"],
        "sesame": ["งา"],
        "peanut": ["ถั่วลิสง", "เนยถั่ว"],
        "treenut": ["เม็ดมะม่วงหิมพานต์", "อัลมอนด์", "วอลนัท"],
        "fish": ["ปลา", "ทูน่า", "แซลมอน"],
        "shellfish": ["กุ้ง", "ปู", "กั้ง", "กุ้งแห้ง"],
        "mollusc": ["หอย", "ปลาหมึก", "หมึก"],
        "fishsauce": ["น้ำปลา"],
        "shrimppaste": ["กะปิ"],
        "msg": ["ผงชูรส"],
        "mushroom": ["เห็ด"],
        "coconut": ["มะพร้าว", "กะทิ"],
    ]

    /// Treffer, die trotz Teilzeichenfolge keine sind: Wort -> was vor/nach der Fundstelle stehen darf nicht.
    /// „ขนม“ (Süßigkeit) enthält „นม“; „ปลาหมึก“ (Tintenfisch) enthält „ปลา“; „หมึก“ ist auch Tinte.
    private static let thaiFalse: [(id: String, hit: String, whole: String)] = [
        ("milk", "นม", "ขนม"), ("milk", "นม", "ขนมปัง"), ("milk", "นม", "ขนมจีน"),
        ("fish", "ปลา", "ปลาหมึก"), ("shellfish", "ปู", "ปูน"), ("sesame", "งา", "งานเลี้ยง"), ("sesame", "งา", "งาน"),
        ("sesame", "งา", "ช้างา"),
    ]

    private static func tokens(_ line: String) -> [String] {
        line.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    private static func latinMatch(_ id: String, _ toks: [String], _ line: String) -> Bool {
        let words = latin[id] ?? []
        let low = line.lowercased()
        for w in words {
            if w.contains(" ") { if low.contains(w) { return true }; continue }
            for t in toks {
                if t == w || t == w + "s" || t == w + "es" { return true }
                if w.count >= 6, t.hasPrefix(w) { return true }
            }
        }
        return false
    }

    private static func thaiMatch(_ id: String, _ line: String) -> Bool {
        guard line.unicodeScalars.contains(where: { (0x0E00...0x0E7F).contains($0.value) }) else { return false }
        for w in thai[id] ?? [] {
            var search = line.startIndex
            while let r = line.range(of: w, range: search..<line.endIndex) {
                // Ausnahmen: steht das Fundstück innerhalb eines bekannten anderen Worts, zählt es nicht.
                let blocked = thaiFalse.contains { f in
                    f.id == id && f.hit == w && containsAround(line, r, f.whole)
                }
                if !blocked { return true }
                search = r.upperBound
            }
        }
        return false
    }

    /// Liegt die Fundstelle `r` innerhalb eines Vorkommens von `whole`?
    private static func containsAround(_ line: String, _ r: Range<String.Index>, _ whole: String) -> Bool {
        var s = line.startIndex
        while let w = line.range(of: whole, range: s..<line.endIndex) {
            if w.lowerBound <= r.lowerBound, w.upperBound >= r.upperBound { return true }
            s = w.upperBound
        }
        return false
    }

    /// Nur „ถั่ว“ ohne Zusatz: Bohne, Erdnuss oder Nuss – nicht sicher.
    private static func thaiBeanMaybe(_ line: String) -> Bool {
        var s = line
        for known in ["ถั่วลิสง", "ถั่วเหลือง", "ถั่วงอก", "ถั่วฝักยาว", "ถั่วเขียว", "ถั่วแดง", "ถั่วดำ"] {
            s = s.replacingOccurrences(of: known, with: " ")
        }
        return s.contains("ถั่ว")
    }

    /// Alle Zeilen, in denen ein vermiedenes Allergen vorkommt (sicher oder möglich), in Kartenreihenfolge.
    static func scan(lines: [String], avoid: Set<String>) -> [Hit] {
        guard !avoid.isEmpty else { return [] }
        var out: [Hit] = []
        for line in lines {
            let toks = tokens(line)
            var ids: [String] = []
            for id in avoid.sorted() where latinMatch(id, toks, line) || thaiMatch(id, line) { ids.append(id) }
            // Fischsauce/Garnelenpaste enthalten Fisch bzw. Krebstier.
            if ids.contains("fishsauce"), avoid.contains("fish"), !ids.contains("fish") { ids.append("fish") }
            if ids.contains("shrimppaste"), avoid.contains("shellfish"), !ids.contains("shellfish") { ids.append("shellfish") }
            var maybe: [String] = []
            if !ids.contains("peanut"), avoid.contains("peanut"), thaiBeanMaybe(line) { maybe.append("peanut") }
            if !ids.contains("treenut"), avoid.contains("treenut"), thaiBeanMaybe(line) { maybe.append("treenut") }
            if !ids.isEmpty || !maybe.isEmpty { out.append(Hit(line: line, ids: ids.sorted(), maybe: maybe)) }
        }
        return out
    }

    /// Ids der Allergien aus den festen Allergie-Sätzen (`Allergen`), die in allergens.json dieselbe Id tragen.
    static func ids(from allergens: [Allergen]) -> Set<String> {
        var s = Set<String>()
        for a in allergens {
            switch a {
            case .gluten: s.formUnion(["gluten", "wheat"])
            default: s.insert(a.rawValue)
            }
        }
        return s
    }
}

// MARK: Reise-Modus

/// Aus dem Land (Standort) werden Partnersprache, Notrufnummern und Währung vorgeschlagen. Nie stilles Umschalten.
enum TravelMode {
    struct Suggestion: Equatable {
        var region: String
        var partner: Lang?
        var emergency: EmergencyNumbers.Set
        var currency: String?
        /// Das Paar würde sich ändern (die Oberfläche fragt nach, statt umzuschalten).
        var changesPair: Bool
    }

    static let languageByRegion: [String: String] = [
        "TH": "th", "DE": "de", "AT": "de", "CH": "de", "ES": "es", "MX": "es", "FR": "fr", "JP": "ja", "KR": "ko",
        "CN": "zh", "TW": "zh", "VN": "vi", "ID": "id", "GB": "en", "US": "en", "AU": "en", "NZ": "en", "SG": "en", "MY": "en",
    ]

    /// `home`: Region des Nutzers (z. B. aus dem Gebietsschema); im Heimatland kein Vorschlag.
    static func suggest(region: String?, home: String?, pair: LangPair) -> Suggestion? {
        guard let region = region?.uppercased(), region.count == 2, region != home?.uppercased() else { return nil }
        let partner = languageByRegion[region].flatMap { Lang(rawValue: $0) }
        let emergency = EmergencyNumbers.forRegion(region)
        let currency = Locale(identifier: "en_\(region)").currency?.identifier
        let changes = partner.map { $0 != pair.partner && $0 != pair.mine } ?? false
        return Suggestion(region: region, partner: partner, emergency: emergency, currency: currency, changesPair: changes)
    }
}

// MARK: Zwei-Geräte-Modus (Nachrichten)

/// Nachricht zwischen zwei iPhones (Prototyp, MultipeerConnectivity). Klein, versioniert, ohne Gesprächsverlauf.
struct PeerMessage: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case hello, text, ack }
    static let version = 1
    static let maxBytes = 4096

    var v = PeerMessage.version
    var kind: Kind
    var id: String
    var lang: String
    var text: String

    static func text(_ text: String, lang: Lang, id: String = UUID().uuidString) -> PeerMessage {
        PeerMessage(kind: .text, id: id, lang: lang.rawValue, text: text)
    }

    func encode() -> Data? {
        guard let d = try? JSONEncoder().encode(self), d.count <= Self.maxBytes else { return nil }
        return d
    }

    /// Zu große, kaputte oder zu neue Nachrichten werden verworfen (nil).
    static func decode(_ data: Data) -> PeerMessage? {
        guard data.count <= maxBytes, let m = try? JSONDecoder().decode(PeerMessage.self, from: data), m.v <= version else { return nil }
        return m
    }
}

/// Zustand der Verbindung und Doppelschutz (WLAN-Wiederholungen liefern dieselbe Nachricht zweimal).
struct PeerState: Sendable {
    enum Phase: Equatable, Sendable { case idle, searching, connected(peer: String) }
    private(set) var phase: Phase = .idle
    private(set) var seen: [String] = []
    static let memory = 64

    mutating func startSearch() { if phase == .idle { phase = .searching } }
    mutating func connected(_ peer: String) { phase = .connected(peer: peer) }
    mutating func lost() { phase = .idle }

    /// Neue Textnachricht? Nur im verbundenen Zustand und nur beim ersten Mal.
    mutating func accept(_ m: PeerMessage) -> Bool {
        guard case .connected = phase, m.kind == .text, !seen.contains(m.id) else { return false }
        seen.append(m.id)
        if seen.count > Self.memory { seen.removeFirst(seen.count - Self.memory) }
        return true
    }
}

// MARK: Aussprache-Coach

/// Vergleicht, was die Erkennung gehört hat, mit dem Soll-Satz. Kein Lautvergleich, sondern Zeichenähnlichkeit: ehrlich als Näherung.
enum PronunciationCoach {
    enum Verdict: Equatable, Sendable { case good, close, retry }
    struct Result: Equatable, Sendable {
        var score: Int
        var verdict: Verdict
        /// Wörter des Soll-Satzes, die in der Erkennung fehlen (nur bei Leerzeichen-Sprachen)
        var missing: [String]
    }

    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let kept = folded.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == " " || (0x0E00...0x0E7F).contains($0.value) }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    static func score(expected: String, heard: String) -> Result {
        let e = normalize(expected), h = normalize(heard)
        guard !e.isEmpty else { return Result(score: 0, verdict: .retry, missing: []) }
        // Thai ohne Leerzeichen: Leerzeichen nicht mitzählen.
        let ec = Array(e.replacingOccurrences(of: " ", with: "")), hc = Array(h.replacingOccurrences(of: " ", with: ""))
        let d = distance(ec, hc)
        let s = max(0, Int((1 - Double(d) / Double(max(ec.count, hc.count, 1))) * 100))
        let heardWords = Set(h.split(separator: " ").map(String.init))
        let missing = e.split(separator: " ").map(String.init).filter { !heardWords.contains($0) }
        let verdict: Verdict = s >= 90 ? .good : (s >= 70 ? .close : .retry)
        return Result(score: s, verdict: verdict, missing: e.contains(" ") ? missing : [])
    }
}

// MARK: Wiederholungs-Planer (FSRS-ähnlich)

/// Vereinfachtes FSRS: Stabilität S (Tage, bis die Abrufwahrscheinlichkeit auf 90 % fällt) und Schwierigkeit D (1…10).
enum SpacedRepetition {
    enum Rating: Int, Sendable, CaseIterable { case again = 1, hard, good, easy }

    struct State: Codable, Equatable, Sendable {
        var stability: Double = 0
        var difficulty: Double = 5
        var due: Date
        var last: Date?
        var reps = 0
        var lapses = 0
    }

    static let retention = 0.9
    static let maxInterval = 365.0

    /// Abrufwahrscheinlichkeit nach `days` Tagen (FSRS-4: R = (1 + t / 9S)^-1).
    static func retrievability(days: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return 1 / (1 + max(0, days) / (9 * stability))
    }

    /// Tage bis die Abrufwahrscheinlichkeit auf `retention` fällt.
    static func interval(stability: Double, retention: Double = SpacedRepetition.retention) -> Double {
        min(maxInterval, max(1, 9 * stability * (1 / retention - 1)))
    }

    static func fresh(now: Date) -> State { State(due: now) }

    static func review(_ s: State, _ rating: Rating, now: Date) -> State {
        var n = s
        n.reps += 1
        let elapsed = s.last.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? 0
        if s.stability <= 0 {
            // erste Wiederholung: Anfangsstabilität je Bewertung
            n.stability = [0.4, 1.2, 3.0, 7.0][rating.rawValue - 1]
            n.difficulty = min(10, max(1, 5 - Double(rating.rawValue - 3) * 1.2))
        } else if rating == .again {
            n.lapses += 1
            n.stability = max(0.3, min(s.stability, 0.5 * pow(s.stability, 0.5)))
            n.difficulty = min(10, s.difficulty + 1)
        } else {
            let r = retrievability(days: elapsed, stability: s.stability)
            let hard = rating == .hard ? 0.6 : 1.0
            let easy = rating == .easy ? 1.6 : 1.0
            let gain = exp(1.0) * (11 - s.difficulty) * pow(s.stability, -0.2) * (exp(0.9 * (1 - r)) - 1 + 0.2)
            n.stability = min(maxInterval, s.stability * (1 + gain * hard * easy))
            n.difficulty = min(10, max(1, s.difficulty - Double(rating.rawValue - 3) * 0.4))
        }
        n.last = now
        let days = rating == .again ? 0 : interval(stability: n.stability)
        n.due = now.addingTimeInterval(days * 86_400 + (rating == .again ? 600 : 0))   // „nochmal“: in 10 Minuten
        return n
    }

    static func isDue(_ s: State, now: Date) -> Bool { s.due <= now }
}

// MARK: Standort-Auslöser (nur im Vordergrund, grob)

enum PlaceKind: String, CaseIterable, Sendable {
    case airport, restaurant, hotel, hospital, market, transit, pharmacy, other

    /// Aus der Kategorie von Apple Karten (`MKPointOfInterestCategory.rawValue`, z. B. „MKPOICategoryAirport“).
    static func from(category: String) -> PlaceKind {
        let c = category.lowercased()
        let table: [(String, PlaceKind)] = [
            ("airport", .airport), ("restaurant", .restaurant), ("cafe", .restaurant), ("bakery", .restaurant),
            ("foodmarket", .market), ("store", .market), ("hotel", .hotel), ("hospital", .hospital),
            ("pharmacy", .pharmacy), ("publictransport", .transit), ("parking", .transit), ("carrental", .transit),
        ]
        return table.first { c.contains($0.0) }?.1 ?? .other
    }

    /// Satzbuch-Themen, die dort jetzt passen (Ids der Pakete/Themen als Schlagwörter).
    var topics: Set<String> {
        switch self {
        case .airport: return ["airport", "transport", "taxi"]
        case .restaurant: return ["food", "restaurant", "allergy"]
        case .hotel: return ["hotel", "accommodation"]
        case .hospital: return ["health", "emergency"]
        case .pharmacy: return ["health", "pharmacy"]
        case .market: return ["shopping", "market", "numbers"]
        case .transit: return ["transport", "taxi", "directions"]
        case .other: return []
        }
    }
}

enum LocationTrigger {
    /// Fällige Karten zuerst, die zum Ort passen; höchstens `limit`. Ohne Ort oder ohne Treffer: leer (keine Störung).
    static func pick<C>(_ cards: [C], tags: (C) -> Set<String>, due: (C) -> Bool, place: PlaceKind, limit: Int = 5) -> [C] {
        let t = place.topics
        guard !t.isEmpty else { return [] }
        return Array(cards.filter { due($0) && !tags($0).isDisjoint(with: t) }.prefix(limit))
    }
}

// MARK: Reise-Tagebuch und Statistik

enum TravelDiary {
    struct Summary: Equatable {
        var turns = 0
        var days = 0
        var longestStreak = 0
        var perLang: [String: Int] = [:]
        var offlinePercent = 0
        var busiest: Date?
    }

    /// Fasst Verlaufseinträge zusammen. Fehlerzeilen und leere Einträge zählen nicht; „offline“ = Apple-Übersetzung oder Satzbuch.
    static func summarize(_ entries: [Entry], calendar: Calendar = .current) -> Summary {
        var s = Summary()
        var perDay: [Date: Int] = [:]
        var offline = 0, translated = 0
        for e in entries where e.error == nil && e.photo != true && !e.text.trimmingCharacters(in: .whitespaces).isEmpty {
            s.turns += 1
            s.perLang[e.src.rawValue, default: 0] += 1
            perDay[calendar.startOfDay(for: e.date), default: 0] += 1
            if let p = e.provider, p != "card" {
                translated += 1
                if p.hasPrefix("apple") || p == "phrasebook" { offline += 1 }
            }
        }
        s.days = perDay.count
        s.offlinePercent = translated == 0 ? 0 : Int((Double(offline) / Double(translated) * 100).rounded())
        s.busiest = perDay.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
        var best = 0, run = 0
        var prev: Date?
        for d in perDay.keys.sorted() {
            if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        s.longestStreak = best
        return s
    }
}

// MARK: Hotelkarte als QR-Text

/// Text für den QR-Code der Hotelkarte (vCard 3.0): der Taxifahrer scannt Name, Adresse und Telefon.
enum HotelCardQR {
    static let maxChars = 900

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: ";", with: "\\;")
    }

    static func payload(name: String, address: String, phone: String = "") -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        var lines = ["BEGIN:VCARD", "VERSION:3.0", "FN:\(esc(n))", "ORG:\(esc(n))"]
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { lines.append("ADR;TYPE=WORK:;;\(esc(a));;;;") }
        let p = phone.filter { $0.isNumber || $0 == "+" }
        if !p.isEmpty { lines.append("TEL;TYPE=WORK:\(p)") }
        lines.append("END:VCARD")
        let text = lines.joined(separator: "\n")
        return text.count <= maxChars ? text : nil
    }
}

// MARK: Uhr (WatchConnectivity-Nachrichten)

/// Nachricht iPhone <-> Apple Watch als Property-List-Wörterbuch (so verlangt es WatchConnectivity). Ohne Watch-Target testbar.
struct WatchPhrase: Equatable, Sendable {
    var text: String
    var translation: String
    var lang: String
    var roman: String?

    static let maxChars = 400

    func encode() -> [String: Any]? {
        guard text.count <= Self.maxChars, translation.count <= Self.maxChars else { return nil }
        var d: [String: Any] = ["v": 1, "text": text, "tr": translation, "lang": lang]
        if let roman { d["roman"] = roman }
        return d
    }

    static func decode(_ d: [String: Any]) -> WatchPhrase? {
        guard (d["v"] as? Int) == 1, let t = d["text"] as? String, let tr = d["tr"] as? String, let l = d["lang"] as? String,
              t.count <= maxChars, tr.count <= maxChars else { return nil }
        return WatchPhrase(text: t, translation: tr, lang: l, roman: d["roman"] as? String)
    }
}

// MARK: Spotlight-Plan

/// Was in den Spotlight-Index kommt. Nur mit Zustimmung (Standard aus), nie bei Face-ID-Sperre des Verlaufs.
enum SpotlightPlan {
    struct Item: Equatable, Sendable {
        var id: String
        var title: String
        var content: String
        var date: Date
    }

    static let limit = 200
    static let domain = "app.dolmetscher.history"

    static func shouldIndex(enabled: Bool, locked: Bool) -> Bool { enabled && !locked }

    static func items(_ entries: [Entry]) -> [Item] {
        entries.reversed().lazy
            .filter { $0.error == nil && $0.photo != true && $0.provider != "card" && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(limit)
            .map { e in
                Item(id: e.id.uuidString, title: e.text, content: [e.translation, e.roman].compactMap { $0 }.joined(separator: " · "), date: e.date)
            }
    }
}

// MARK: Bereitschafts-Ampel

/// Qualität der installierten Stimme einer Sprache.
enum VoiceQuality: Int, Comparable, Sendable {
    case none, compact, enhanced, premium
    static func < (a: VoiceQuality, b: VoiceQuality) -> Bool { a.rawValue < b.rawValue }
}

enum ReadinessLight: Equatable, Sendable {
    /// bereit, auch mit guter (erweiterter oder Premium-)Stimme für die Partnersprache
    case green
    /// geht ohne Netz, aber nur mit einfacher Stimme – oder etwas Ladbares fehlt noch
    case yellow
    /// ohne Netz nicht nutzbar (Bausteine fehlen oder gibt es nicht)
    case red

    static func evaluate(_ r: OfflineReport, partnerVoice: VoiceQuality) -> ReadinessLight {
        let blocking = r.items.contains { item in
            switch item.kind {
            case .voice: return false
            default: return item.state != .ready
            }
        }
        if blocking { return .red }
        if partnerVoice == .none { return .red }
        return partnerVoice >= .enhanced && r.isReady ? .green : .yellow
    }

    var textKey: String {
        switch self {
        case .green: return "r33_light_green"
        case .yellow: return "r33_light_yellow"
        case .red: return "r33_light_red"
        }
    }
}

// MARK: Backup-Ausschluss und Dateischutz

enum FileGuard {
    enum Protection: Equatable, Sendable { case untilFirstUnlock, complete, none }
    struct Policy: Equatable, Sendable {
        var excludeFromBackup: Bool
        var protection: Protection
    }

    /// Nutzerdaten (Verlauf, Karten, Favoriten, Karten mit Gesundheitsdaten) bleiben auf dem Gerät und sind geschützt;
    /// Zwischenspeicher und Modelle (neu ladbar) gehören nicht ins Backup; Exportdateien sind Sache des Nutzers.
    static func policy(forFileNamed name: String) -> Policy {
        let n = name.lowercased()
        if n.hasPrefix("export") || n.hasSuffix(".csv") || n.hasSuffix(".txt") || n.hasSuffix(".md") {
            return Policy(excludeFromBackup: false, protection: .untilFirstUnlock)
        }
        if n.contains("medical") || n.contains("emergency") || n.contains("card") { return Policy(excludeFromBackup: true, protection: .complete) }
        return Policy(excludeFromBackup: true, protection: .untilFirstUnlock)
    }
}

// MARK: Umweg-Beschriftung (Brücke über Englisch)

enum PivotLabel {
    static let provider = "apple-pivot"
    static func isPivot(_ provider: String?) -> Bool { provider == Self.provider }

    /// „th → en → de“
    static func route(src: Lang, dst: Lang) -> String { "\(src.rawValue) → en → \(dst.rawValue)" }
}
