// Round22.swift – weitere Reise-Helfer: Handeln (Gegenangebote), Thai-Datum.
// Reine Logik, in Round22Tests belegt; die Ansicht hängt in TravelHelpersView.
import Foundation

/// Gegenangebote beim Handeln (Markt, Tuk-Tuk): Anteile des verlangten Preises, auf runde Beträge, mit Thai-Zahlwort.
enum Bargain {
    struct Offer: Equatable, Identifiable {
        var percent: Int
        var amount: Int
        var words: String
        var id: Int { percent }
    }

    static let percents = [50, 60, 70, 80]

    /// Rundung: unter 100 ฿ auf 5, darüber auf 10 (so nennt man Preise).
    static func round(_ v: Double) -> Int {
        let step = v < 100 ? 5.0 : 10.0
        return max(Int((v / step).rounded()) * Int(step), Int(step))
    }

    static func offers(asking: Double) -> [Offer] {
        guard asking.isFinite, asking >= 20, asking < 1_000_000 else { return [] }
        var seen = Set<Int>()
        return percents.compactMap { p in
            let amount = round(asking * Double(p) / 100)
            guard amount < Int(asking), seen.insert(amount).inserted, let w = ThaiNumber.words(amount) else { return nil }
            return Offer(percent: p, amount: amount, words: w + "บาท")
        }
    }
}

/// Datum auf Thai (buddhistisches Jahr): „วันศุกร์ที่ 20 พฤศจิกายน พ.ศ. 2569“, gesprochen mit Zahlwörtern.
enum ThaiDate {
    static let weekdays = ["อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัสบดี", "ศุกร์", "เสาร์"]
    static let months = ["มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
                         "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"]

    static func text(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian), spoken: Bool = false) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let y = c.year, let m = c.month, let d = c.day, let w = c.weekday,
              (1...12).contains(m), (1...7).contains(w) else { return "" }
        let by = y + 543
        let day = spoken ? (ThaiNumber.words(d) ?? "\(d)") : "\(d)"
        let year = spoken ? (ThaiNumber.words(by) ?? "\(by)") : "\(by)"
        return "วัน\(weekdays[w - 1])ที่ \(day) \(months[m - 1]) พ.ศ. \(year)"
    }
}
