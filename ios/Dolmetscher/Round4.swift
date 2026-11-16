// Round4.swift – reine Logik für Runde 4: Thai-Zahlwörter lesen, Preise erkennen, Auto-Stopp mit Vorwarnung,
// Wärme/Energiesparmodus, Vorlese-Stau, Reise-Vorbereitung, Ziele, Speisen-Lexikon, buddhistisches Jahr.
// Ohne Geräte-APIs, unit-getestet (Round4Tests).
import Foundation

extension ThaiNumber {
    private static let digitWords: [(String, Int)] = [
        ("ศูนย์", 0), ("หนึ่ง", 1), ("เอ็ด", 1), ("สอง", 2), ("ยี่", 2), ("สาม", 3), ("สี่", 4), ("ห้า", 5),
        ("หก", 6), ("เจ็ด", 7), ("แปด", 8), ("เก้า", 9),
    ]
    private static let placeWords: [(String, Int)] = [("สิบ", 10), ("ร้อย", 100), ("พัน", 1_000), ("หมื่น", 10_000), ("แสน", 100_000)]

    /// Alle Wörter, aus denen ein Zahlwort besteht (für die Suche im Text).
    static var tokens: [String] { digitWords.map(\.0) + placeWords.map(\.0) + ["ล้าน"] }

    /// „สามร้อยห้าสิบ“ -> 350, „ยี่สิบเอ็ด“ -> 21, „หนึ่งล้านสองแสน“ -> 1 200 000. Nil, wenn es kein Zahlwort ist.
    static func parse(_ raw: String) -> Int? {
        var rest = Substring(raw.filter { !$0.isWhitespace })
        guard !rest.isEmpty else { return nil }
        var total = 0, section = 0
        var pending: Int?
        while !rest.isEmpty {
            if rest.hasPrefix("ล้าน") {
                let value = section + (pending ?? 0)
                total = (total + (value == 0 ? 1 : value)) * 1_000_000
                section = 0; pending = nil
                rest = rest.dropFirst("ล้าน".count)
            } else if let (w, v) = placeWords.first(where: { rest.hasPrefix($0.0) }) {
                section += (pending ?? 1) * v
                pending = nil
                rest = rest.dropFirst(w.count)
            } else if let (w, v) = digitWords.first(where: { rest.hasPrefix($0.0) }) {
                guard pending == nil else { return nil }   // zwei Ziffern hintereinander: kein Zahlwort
                pending = v
                rest = rest.dropFirst(w.count)
            } else {
                return nil
            }
        }
        return total + section + (pending ?? 0)
    }
}

/// Preise in einem Text (Übersetzung, Speisekarte, Gehörtes): ฿120, 120 บาท, 1,200 baht, ๑๒๐ บาท, สามร้อยบาท.
enum PriceSpotter {
    /// Thai-Ziffern ๐–๙ in 0–9.
    static func asciiDigits(_ s: String) -> String {
        String(s.unicodeScalars.map { u -> Character in
            (0x0E50...0x0E59).contains(u.value) ? Character(String(u.value - 0x0E50)) : Character(u)
        })
    }

    private static let numeric = try! NSRegularExpression(
        pattern: #"฿\s*(\d[\d.,]*)|(\d[\d.,]*)\s*(?:฿|บาท|baht|bath|thb)"#, options: [.caseInsensitive])
    private static let words = try! NSRegularExpression(
        pattern: "((?:" + ThaiNumber.tokens.joined(separator: "|") + ")+)\\s*บาท")

    static func amounts(in text: String) -> [Double] {
        let s = asciiDigits(text)
        let r = NSRange(s.startIndex..., in: s)
        var out: [Double] = []
        for m in numeric.matches(in: s, range: r) {
            let g = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            guard let range = Range(g, in: s) else { continue }
            let raw = String(s[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if let v = AmountParser.parse(raw), v > 0 { out.append(v) }
        }
        for m in words.matches(in: s, range: r) {
            guard let range = Range(m.range(at: 1), in: s), let v = ThaiNumber.parse(String(s[range])), v > 0 else { continue }
            out.append(Double(v))
        }
        var seen = Set<Double>()
        return Array(out.filter { seen.insert($0).inserted }.prefix(3))
    }

    /// „฿350 ≈ 9,10 €“ – Heimatwährung im Format der Oberflächensprache.
    static func line(_ amounts: [Double], rate: Double, code: String, locale: Locale) -> String? {
        guard !amounts.isEmpty, rate > 0, code.count == 3 else { return nil }
        return amounts.map { a in
            let home = (a * rate).formatted(.currency(code: code.uppercased()).locale(locale))
            return "฿\(a.formatted(.number.locale(locale))) ≈ \(home)"
        }.joined(separator: " · ")
    }
}

/// Auto-Stopp: 30 s vorher warnen, im Energiesparmodus höchstens 3 Minuten.
enum IdlePolicy {
    enum State: Equatable { case ok, warn, stop }
    static let warnSeconds: Double = 30

    /// Sekunden bis zum Auto-Stopp; nil = nie.
    static func limit(minutes: Int, lowPower: Bool) -> Double? {
        guard minutes > 0 else { return nil }
        return Double(lowPower ? min(minutes, 3) : minutes) * 60
    }

    static func state(idle: Double, limit: Double?) -> State {
        guard let limit else { return .ok }
        if idle >= limit { return .stop }
        return idle >= limit - warnSeconds ? .warn : .ok
    }
}

/// Wärme: ab „ernst“ nur noch eine Sprache erkennen (halbe Rechenlast) und keine Live-Vorschau.
enum EnergyPolicy {
    static func hot(_ t: ProcessInfo.ThermalState) -> Bool { t == .serious || t == .critical }

    /// Welche Richtung bei Hitze? Die Sprache, die als Nächstes zu erwarten ist (Gegenteil des letzten Satzes).
    static func coolMode(pair: LangPair, lastSpoken: Lang?) -> Direction {
        guard let last = lastSpoken, pair.contains(last) else { return .mine }
        return pair.other(last) == pair.mine ? .mine : .partner
    }
}

/// Vorlese-Stau: Wartet ein automatisch vorzulesender Satz hinter zu vielen neueren, wird er übersprungen.
enum SpeechBacklog {
    static let maxBehind = 2
    static func skip(seq: Int, latest: Int) -> Bool { latest - seq >= maxBehind }
}

/// Reise-Vorbereitung: Ist alles da, damit die App ohne Netz funktioniert?
struct ReadinessReport: Equatable {
    enum Item: String, CaseIterable { case recognizer, translation, voice, permission }

    var recognizerMine: Readiness = .downloadable
    var recognizerPartner: Readiness = .downloadable
    var translation: Readiness = .downloadable
    var voiceMine = false
    var voicePartner = false
    /// nil = noch nicht gefragt
    var micAllowed: Bool?

    func ok(_ item: Item) -> Bool {
        switch item {
        case .recognizer: return recognizerMine == .installed && recognizerPartner == .installed
        case .translation: return translation == .installed
        case .voice: return voiceMine && voicePartner
        case .permission: return micAllowed == true
        }
    }

    var allReady: Bool { Item.allCases.allSatisfy(ok) }
    var missing: [Item] { Item.allCases.filter { !ok($0) } }

    /// Zwei Richtungen zu einer: beide installiert = installiert, eine fehlt ganz = gibt es nicht.
    static func combine(_ a: Readiness, _ b: Readiness) -> Readiness {
        if a == .unsupported || b == .unsupported { return .unsupported }
        return a == .installed && b == .installed ? .installed : .downloadable
    }
}

/// Gespeichertes Ziel für Taxi/Tuk-Tuk: Name für mich, Name/Adresse in der Landessprache zum Zeigen.
struct Place: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// Thai-Name oder Adresse (von der Visitenkarte abgeschrieben oder per Foto-Text)
    var local: String
    var note = ""

    /// Für Apple Karten: der Name, den der Fahrer lesen kann, sonst der eigene.
    var mapsURL: URL? {
        let q = local.isEmpty ? name : local
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "q", value: q)]
        return c?.url
    }

    /// „Bitte bringen Sie mich hierhin“ in Thai, mit Höflichkeitsform.
    static func takeMeThai(_ polite: Politeness) -> String { polite.fill("ช่วยพาไปที่นี่หน่อย{p}") }
}

/// Kleines Offline-Lexikon thailändischer Gerichte – maschinelle Übersetzung ist bei Speisenamen unzuverlässig.
struct Dish: Equatable, Sendable {
    enum Note: String, CaseIterable, Sendable { case spicy, peanut, fishSauce, shrimpPaste, seafood, pork }
    var th: String
    var roman: String
    var en: String
    var de: String
    var notes: [Note]
}

enum Dishes {
    static let all: [Dish] = [
        Dish(th: "ผัดกะเพรา", roman: "phat kra-phao", en: "Stir-fried holy basil with chili", de: "Gebratenes mit Thai-Basilikum und Chili", notes: [.spicy, .fishSauce]),
        Dish(th: "ต้มยำกุ้ง", roman: "tom yam kung", en: "Hot and sour shrimp soup", de: "Scharf-saure Garnelensuppe", notes: [.spicy, .seafood, .fishSauce]),
        Dish(th: "ต้มยำ", roman: "tom yam", en: "Hot and sour soup", de: "Scharf-saure Suppe", notes: [.spicy, .fishSauce]),
        Dish(th: "ต้มข่าไก่", roman: "tom kha kai", en: "Chicken coconut soup with galangal", de: "Hühnersuppe mit Kokos und Galgant", notes: [.fishSauce]),
        Dish(th: "ส้มตำ", roman: "som tam", en: "Green papaya salad", de: "Papayasalat", notes: [.spicy, .peanut, .fishSauce, .shrimpPaste]),
        Dish(th: "ผัดไทย", roman: "phat thai", en: "Pad Thai (fried rice noodles)", de: "Pad Thai (gebratene Reisnudeln)", notes: [.peanut, .fishSauce, .seafood]),
        Dish(th: "ผัดซีอิ๊ว", roman: "phat si-io", en: "Wide noodles with soy sauce", de: "Breite Nudeln mit Sojasauce", notes: []),
        Dish(th: "ข้าวผัด", roman: "khao phat", en: "Fried rice", de: "Gebratener Reis", notes: [.fishSauce]),
        Dish(th: "ข้าวมันไก่", roman: "khao man kai", en: "Chicken rice", de: "Hähnchen mit Reis", notes: []),
        Dish(th: "ข้าวขาหมู", roman: "khao kha mu", en: "Stewed pork leg on rice", de: "Geschmorte Schweinshaxe mit Reis", notes: [.pork]),
        Dish(th: "ข้าวเหนียวมะม่วง", roman: "khao niao ma-muang", en: "Mango sticky rice", de: "Klebreis mit Mango", notes: []),
        Dish(th: "แกงเขียวหวาน", roman: "kaeng khiao wan", en: "Green curry", de: "Grünes Curry", notes: [.spicy, .shrimpPaste, .fishSauce]),
        Dish(th: "แกงแดง", roman: "kaeng daeng", en: "Red curry", de: "Rotes Curry", notes: [.spicy, .shrimpPaste, .fishSauce]),
        Dish(th: "แกงมัสมั่น", roman: "kaeng mat-sa-man", en: "Massaman curry", de: "Massaman-Curry", notes: [.peanut, .shrimpPaste]),
        Dish(th: "พะแนง", roman: "pha-naeng", en: "Panang curry", de: "Panang-Curry", notes: [.spicy, .peanut, .shrimpPaste]),
        Dish(th: "แกงส้ม", roman: "kaeng som", en: "Sour curry", de: "Saures Curry", notes: [.spicy, .shrimpPaste, .seafood]),
        Dish(th: "ลาบ", roman: "lap", en: "Spicy minced meat salad", de: "Scharfer Hackfleischsalat", notes: [.spicy, .fishSauce]),
        Dish(th: "น้ำตก", roman: "nam tok", en: "Grilled meat salad", de: "Salat mit gegrilltem Fleisch", notes: [.spicy, .fishSauce]),
        Dish(th: "ยำวุ้นเส้น", roman: "yam wun sen", en: "Glass noodle salad", de: "Glasnudelsalat", notes: [.spicy, .seafood, .fishSauce]),
        Dish(th: "หมูกระทะ", roman: "mu kra-tha", en: "Thai barbecue hot pot", de: "Thai-Grill mit Brühe", notes: [.pork]),
        Dish(th: "หมูปิ้ง", roman: "mu ping", en: "Grilled pork skewers", de: "Gegrillte Schweinespieße", notes: [.pork]),
        Dish(th: "ไก่ย่าง", roman: "kai yang", en: "Grilled chicken", de: "Gegrilltes Hähnchen", notes: []),
        Dish(th: "ปลาเผา", roman: "pla phao", en: "Salt-crusted grilled fish", de: "Gegrillter Fisch in Salzkruste", notes: [.seafood]),
        Dish(th: "ห่อหมก", roman: "ho mok", en: "Steamed fish curry", de: "Gedämpftes Fisch-Curry", notes: [.spicy, .seafood, .shrimpPaste]),
        Dish(th: "ข้าวซอย", roman: "khao soi", en: "Curry noodle soup", de: "Curry-Nudelsuppe", notes: [.spicy, .shrimpPaste]),
        Dish(th: "ก๋วยเตี๋ยว", roman: "kuai tiao", en: "Noodle soup", de: "Nudelsuppe", notes: [.fishSauce]),
        Dish(th: "สะเต๊ะ", roman: "sa-te", en: "Satay with peanut sauce", de: "Saté mit Erdnusssauce", notes: [.peanut]),
        Dish(th: "ปอเปี๊ยะ", roman: "po-pia", en: "Spring rolls", de: "Frühlingsrollen", notes: []),
        Dish(th: "ทอดมัน", roman: "thot man", en: "Fish cakes", de: "Fischküchlein", notes: [.seafood, .shrimpPaste]),
        Dish(th: "น้ำพริก", roman: "nam phrik", en: "Chili dip", de: "Chili-Dip", notes: [.spicy, .shrimpPaste]),
        Dish(th: "ผัดผักบุ้ง", roman: "phat phak bung", en: "Stir-fried morning glory", de: "Gebratener Wasserspinat", notes: [.spicy, .fishSauce]),
        Dish(th: "ไข่เจียว", roman: "khai jiao", en: "Thai omelette", de: "Thai-Omelett", notes: []),
    ]

    /// Gerichte, deren Thai-Name in der Zeile vorkommt – längste zuerst (ต้มยำกุ้ง vor ต้มยำ).
    static func find(_ line: String) -> [Dish] {
        let compact = line.filter { !$0.isWhitespace }
        var found: [Dish] = []
        for d in all.sorted(by: { $0.th.count > $1.th.count }) where compact.contains(d.th) {
            if !found.contains(where: { $0.th.contains(d.th) }) { found.append(d) }
        }
        return found
    }
}

/// Buddhistisches Jahr (Etiketten, Medikamente: „EXP 12/2570“) -> gregorianisch (−543).
enum BuddhistYear {
    private static let rx = try! NSRegularExpression(pattern: #"(?<!\d)(25[5-9]\d)(?!\d)"#)

    /// Gefundene Jahre als „2570 = 2027“.
    static func notes(in text: String) -> [String] {
        let s = PriceSpotter.asciiDigits(text)
        let r = NSRange(s.startIndex..., in: s)
        var seen = Set<Int>()
        return rx.matches(in: s, range: r).compactMap { m in
            guard let range = Range(m.range(at: 1), in: s), let y = Int(s[range]), seen.insert(y).inserted else { return nil }
            return "\(y) = \(y - 543)"
        }
    }
}
