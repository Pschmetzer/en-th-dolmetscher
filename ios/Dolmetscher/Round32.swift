// Round32.swift – testbare Logik der Runde 32: Speicher-Schema und Migration, Notrufnummern je Land, Taxi-Karte,
// Preis-/Verhandlungshilfe, Wort-Lexikon zum Antippen, Bildschirmschutz. Keine Oberfläche (die steht in Round32Views.swift).
import Foundation

// MARK: Speicher-Schema und Migration

/// Version der Dateien in Application Support. `schema.json` hält den Stand; fehlt die Datei, gilt Version 1 (alles vor Runde 32).
/// Jeder Schritt läuft genau einmal und muss wiederholbar sein (App kann mittendrin beendet werden).
enum StorageSchema {
    static let current = 2
    static let file = "schema.json"
    private struct Stamp: Codable { var version: Int }

    /// Schritte `n -> n+1`; Schlüssel ist die Zielversion.
    static func steps(_ store: JSONStore) -> [Int: () -> Void] {
        [2: {
            // v2: Rest-Sicherungen und angefangene Schreibversuche früherer Läufe wegräumen; Daten bleiben unberührt.
            let dir = store.dir
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for n in names where n.hasSuffix(".tmp") { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
        }]
    }

    static func version(_ store: JSONStore) -> Int {
        store.load(Stamp.self, file).value?.version ?? 1
    }

    /// Bringt den Speicher auf `current`. Neuere Version (App zurückgesetzt): nichts anfassen, nichts herabstufen.
    @discardableResult
    static func migrate(_ store: JSONStore) -> Int {
        var v = version(store)
        guard v < current else { return v }
        guard FileManager.default.fileExists(atPath: store.dir.path) else { return v }   // frische Installation: nichts zu migrieren
        let table = steps(store)
        while v < current {
            v += 1
            table[v]?()
            store.store(Stamp(version: v), file)
        }
        return v
    }
}

// MARK: Notrufnummern je Land

enum EmergencyNumbers {
    struct Set: Equatable {
        var region: String
        var police: String, ambulance: String, fire: String
        var extra: [(label: String, number: String)] = []
        static func == (a: Set, b: Set) -> Bool { a.region == b.region && a.police == b.police && a.ambulance == b.ambulance && a.fire == b.fire }
    }

    static let table: [String: Set] = [
        "TH": Set(region: "TH", police: "191", ambulance: "1669", fire: "199", extra: [("Tourist police", "1155")]),
        "DE": Set(region: "DE", police: "110", ambulance: "112", fire: "112"),
        "AT": Set(region: "AT", police: "133", ambulance: "144", fire: "122"),
        "CH": Set(region: "CH", police: "117", ambulance: "144", fire: "118"),
        "US": Set(region: "US", police: "911", ambulance: "911", fire: "911"),
        "CA": Set(region: "CA", police: "911", ambulance: "911", fire: "911"),
        "GB": Set(region: "GB", police: "999", ambulance: "999", fire: "999", extra: [("EU/GSM", "112")]),
        "FR": Set(region: "FR", police: "17", ambulance: "15", fire: "18", extra: [("EU", "112")]),
        "ES": Set(region: "ES", police: "091", ambulance: "061", fire: "080", extra: [("EU", "112")]),
        "IT": Set(region: "IT", police: "112", ambulance: "118", fire: "115"),
        "JP": Set(region: "JP", police: "110", ambulance: "119", fire: "119"),
        "KR": Set(region: "KR", police: "112", ambulance: "119", fire: "119"),
        "CN": Set(region: "CN", police: "110", ambulance: "120", fire: "119"),
        "VN": Set(region: "VN", police: "113", ambulance: "115", fire: "114"),
        "ID": Set(region: "ID", police: "110", ambulance: "118", fire: "113"),
        "AU": Set(region: "AU", police: "000", ambulance: "000", fire: "000", extra: [("GSM", "112")]),
        "NZ": Set(region: "NZ", police: "111", ambulance: "111", fire: "111"),
        "MY": Set(region: "MY", police: "999", ambulance: "999", fire: "994", extra: [("GSM", "112")]),
        "SG": Set(region: "SG", police: "999", ambulance: "995", fire: "995"),
        "IN": Set(region: "IN", police: "100", ambulance: "102", fire: "101", extra: [("All", "112")]),
    ]
    /// Europäische Länder ohne eigenen Eintrag und Mobilfunk überall: 112 wird fast weltweit weitergeleitet.
    static let fallback = Set(region: "ZZ", police: "112", ambulance: "112", fire: "112")

    static func forRegion(_ code: String?) -> Set {
        guard let code = code?.uppercased() else { return fallback }
        return table[code] ?? fallback
    }

    /// Land aus Freitext („Thailand“, „thailand“, „TH“, „Germany“) – für den Kurzbefehl mit Eingabe.
    static func region(matching text: String, locale: Locale = Locale(identifier: "en")) -> String? {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        if q.count == 2, table[q.uppercased()] != nil { return q.uppercased() }
        let locales = [locale, Locale(identifier: "de"), Locale(identifier: "th")]
        for code in table.keys {
            for l in locales where l.localizedString(forRegionCode: code)?.lowercased() == q { return code }
        }
        return nil
    }

    static func summary(_ s: Set) -> String {
        var parts = ["Police \(s.police)", "Ambulance \(s.ambulance)", "Fire \(s.fire)"]
        for e in s.extra { parts.append("\(e.label) \(e.number)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Taxi-Karte

enum TaxiCard {
    struct Item: Identifiable, Equatable {
        let id: String
        let icon: String
        let en: String
        let th: String          // mit Platzhaltern {p} {q} {i}
        let roman: String
    }

    static let items: [Item] = [
        Item(id: "airport", icon: "airplane", en: "To Suvarnabhumi Airport", th: "ไปสนามบินสุวรรณภูมิ{p}", roman: "bpai sà-nǎam-bin sù-wan-ná-puum"),
        Item(id: "donmueang", icon: "airplane.departure", en: "To Don Mueang Airport", th: "ไปสนามบินดอนเมือง{p}", roman: "bpai sà-nǎam-bin dɔɔn-mʉang"),
        Item(id: "bts", icon: "tram.fill", en: "To the BTS / MRT station", th: "ไปสถานีรถไฟฟ้า{p}", roman: "bpai sà-tǎa-nii rót-fai-fáa"),
        Item(id: "meter", icon: "gauge.with.needle", en: "Please use the meter", th: "เปิดมิเตอร์ด้วย{p}", roman: "bpə̀ət mí-dtə̂ə dûai"),
        Item(id: "price", icon: "bahtsign.circle", en: "How much to go here?", th: "ไปที่นี่ราคาเท่าไร{q}", roman: "bpai tîi-nîi raa-kaa tâo-rai"),
        Item(id: "toll", icon: "road.lanes", en: "Take the expressway, please", th: "ขึ้นทางด่วนได้ไหม{q}", roman: "kʉ̂n taang-dùan dâai-măi"),
        Item(id: "stop", icon: "hand.raised.fill", en: "Stop here, please", th: "จอดตรงนี้{p}", roman: "jàwt dtrong-níi"),
        Item(id: "wait", icon: "clock", en: "Please wait a moment", th: "รอสักครู่{p}", roman: "rɔɔ sàk-krûu"),
        Item(id: "aircon", icon: "snowflake", en: "Please turn on the air-con", th: "ช่วยเปิดแอร์หน่อย{p}", roman: "chûai bpə̀ət ae nɔ̀i"),
    ]

    /// Thai mit Höflichkeitswort; der Hotel-/Zielname der Notfallkarte wird nicht erfunden, sondern als Adresse gezeigt.
    static func thai(_ item: Item, female: Bool) -> String { PhraseData.fill(item.th, female: female) }

    static func item(_ id: String) -> Item? { items.first { $0.id == id } }
}

// MARK: Preis- und Verhandlungshilfe

enum PriceHelper {
    struct Offer: Equatable, Identifiable {
        var id: Int { amount }
        let amount: Int
        let label: String      // Schlüsselwort: "first", "fair", "last"
    }

    /// Gegenangebote bei Märkten/Tuk-Tuk: erstes Angebot etwa die Hälfte, dann Mitte, dann knapp darunter.
    /// Auf volle 10 Baht gerundet (kleine Beträge auf 5), nie über dem verlangten Preis, nie unter 5.
    static func counters(asked: Int) -> [Offer] {
        guard asked > 0 else { return [] }
        let steps: [(Double, String)] = [(0.5, "first"), (0.65, "fair"), (0.8, "last")]
        var out: [Offer] = []
        for (f, label) in steps {
            let a = round(Double(asked) * f, to: asked < 100 ? 5 : 10)
            let v = min(max(a, 5), asked)
            if !out.contains(where: { $0.amount == v }) { out.append(Offer(amount: v, label: label)) }
        }
        return out
    }

    private static func round(_ x: Double, to unit: Int) -> Int { Int((x / Double(unit)).rounded()) * unit }

    /// Sätze fürs Handeln (Thai mit Platzhaltern; Umschrift und Deutsch/Englisch dazu).
    static let phrases: [(id: String, en: String, th: String, roman: String)] = [
        ("expensive", "That's too expensive", "แพงไป{p}", "pɛɛng bpai"),
        ("discount", "Can you give a discount?", "ลดหน่อยได้ไหม{q}", "lót nɔ̀i dâai-măi"),
        ("lower", "Can you go lower?", "ลดอีกได้ไหม{q}", "lót ìik dâai-măi"),
        ("last", "What is your best price?", "ราคาที่ดีที่สุดเท่าไร{q}", "raa-kaa tîi dii tîi-sùt tâo-rai"),
        ("pass", "No thanks, I'll look around", "ไม่เป็นไร{p} ขอดูก่อน", "mâi-bpen-rai kɔ̌ɔ duu gɔ̀ɔn"),
    ]

    /// Zeigt der Betrag „Gegenangebot“: Thai-Zahlwort plus „บาท“.
    static func thaiWords(_ amount: Int) -> String? { ThaiNumber.words(amount).map { $0 + "บาท" } }
}

// MARK: Wort-Lexikon zum Antippen

enum WordLexicon {
    struct Entry: Equatable { let roman: String; let meaning: String }

    /// Kleiner eingebauter Grundwortschatz für Reise-Sätze (Thai -> Umschrift, Bedeutung auf Englisch).
    static let entries: [String: Entry] = [
        "สวัสดี": Entry(roman: "sà-wàt-dii", meaning: "hello"),
        "ขอบคุณ": Entry(roman: "kɔ̀ɔp-kun", meaning: "thank you"),
        "ขอโทษ": Entry(roman: "kɔ̌ɔ-tôot", meaning: "sorry / excuse me"),
        "ครับ": Entry(roman: "kráp", meaning: "polite particle (male)"),
        "ค่ะ": Entry(roman: "kâ", meaning: "polite particle (female)"),
        "คะ": Entry(roman: "ká", meaning: "question particle (female)"),
        "ไป": Entry(roman: "bpai", meaning: "go"),
        "มา": Entry(roman: "maa", meaning: "come"),
        "ที่นี่": Entry(roman: "tîi-nîi", meaning: "here"),
        "ตรงนี้": Entry(roman: "dtrong-níi", meaning: "right here"),
        "จอด": Entry(roman: "jàwt", meaning: "stop / park"),
        "รอ": Entry(roman: "rɔɔ", meaning: "wait"),
        "สักครู่": Entry(roman: "sàk-krûu", meaning: "a moment"),
        "ราคา": Entry(roman: "raa-kaa", meaning: "price"),
        "เท่าไร": Entry(roman: "tâo-rai", meaning: "how much"),
        "แพง": Entry(roman: "pɛɛng", meaning: "expensive"),
        "ลด": Entry(roman: "lót", meaning: "reduce / discount"),
        "หน่อย": Entry(roman: "nɔ̀i", meaning: "a little"),
        "ได้": Entry(roman: "dâai", meaning: "can / possible"),
        "ไหม": Entry(roman: "măi", meaning: "question particle"),
        "ไม่": Entry(roman: "mâi", meaning: "not / no"),
        "สนามบิน": Entry(roman: "sà-nǎam-bin", meaning: "airport"),
        "โรงแรม": Entry(roman: "roong-rɛɛm", meaning: "hotel"),
        "ห้องน้ำ": Entry(roman: "hɔ̂ng-náam", meaning: "toilet"),
        "ช่วยด้วย": Entry(roman: "chûai dûai", meaning: "help!"),
        "ตำรวจ": Entry(roman: "dtam-rùat", meaning: "police"),
        "โรงพยาบาล": Entry(roman: "roong-pá-yaa-baan", meaning: "hospital"),
        "หมอ": Entry(roman: "mɔ̌ɔ", meaning: "doctor"),
        "มิเตอร์": Entry(roman: "mí-dtə̂ə", meaning: "meter"),
        "เปิด": Entry(roman: "bpə̀ət", meaning: "open / turn on"),
        "ปิด": Entry(roman: "bpìt", meaning: "close / turn off"),
        "แอร์": Entry(roman: "ae", meaning: "air-con"),
        "ทางด่วน": Entry(roman: "taang-dùan", meaning: "expressway"),
        "ขึ้น": Entry(roman: "kʉ̂n", meaning: "go up / take"),
        "บาท": Entry(roman: "bàat", meaning: "baht"),
        "น้ำ": Entry(roman: "náam", meaning: "water"),
        "อาหาร": Entry(roman: "aa-hǎan", meaning: "food"),
        "เผ็ด": Entry(roman: "pèt", meaning: "spicy"),
        "ช่วย": Entry(roman: "chûai", meaning: "help"),
        "ต้องการ": Entry(roman: "dtɔ̂ng-gaan", meaning: "need / want"),
        "ฉัน": Entry(roman: "chǎn", meaning: "I (female)"),
        "ผม": Entry(roman: "pǒm", meaning: "I (male)"),
    ]

    private static let keysByLength: [String] = entries.keys.sorted { $0.count > $1.count }

    struct Token: Equatable, Identifiable {
        let id: Int
        let text: String
        let entry: Entry?
    }

    /// Längster-Treffer-Zerlegung ohne Wörterbuch-Bibliothek: bekannte Wörter werden Tokens, Leerzeichen trennen,
    /// unbekannte Zeichenfolgen bleiben zusammen (ein Token ohne Eintrag).
    static func tokens(_ text: String) -> [Token] {
        var out: [Token] = []
        var unknown = ""
        func flushUnknown() {
            if !unknown.isEmpty { out.append(Token(id: out.count, text: unknown, entry: nil)); unknown = "" }
        }
        var i = text.startIndex
        while i < text.endIndex {
            let rest = text[i...]
            if let c = text[i...].first, c.isWhitespace || c.isPunctuation {
                flushUnknown(); i = text.index(after: i); continue
            }
            if let key = keysByLength.first(where: { rest.hasPrefix($0) }) {
                flushUnknown()
                out.append(Token(id: out.count, text: key, entry: entries[key]))
                i = text.index(i, offsetBy: key.count)
            } else {
                unknown.append(text[i]); i = text.index(after: i)
            }
        }
        flushUnknown()
        return out
    }
}

// MARK: Bildschirmschutz (Aufnahme, Spiegelung)

enum ScreenShieldPolicy {
    /// Deckt der Schutz den Inhalt zu? Nur sensible Ansichten, nur während Aufnahme/Spiegelung, und nur wenn der Nutzer
    /// die Funktion nicht abgeschaltet hat (Standard: an).
    static func covers(captured: Bool, sensitive: Bool, enabled: Bool = true) -> Bool {
        captured && sensitive && enabled
    }
}
