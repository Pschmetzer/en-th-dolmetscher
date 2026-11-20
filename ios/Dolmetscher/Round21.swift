// Round21.swift – Reise-Helfer (Trinkgeld/Rechnung teilen, Einheiten, Thai-Uhrzeit, Telefonnummer vorlesen)
// und Aufräumen von Export-Dateien. Reine Logik, in Round21Tests belegt.
import Foundation
import SwiftUI

/// Rechnung mit Trinkgeld auf Personen verteilen (ganze Baht, je Person aufgerundet).
enum BillSplit {
    struct Result: Equatable { var tip: Double; var total: Double; var perPerson: Double }

    static let maxPeople = 50

    static func split(bill: Double, tipPercent: Double, people: Int) -> Result? {
        guard bill.isFinite, bill >= 0, bill < 1e9, tipPercent.isFinite, (0...100).contains(tipPercent) else { return nil }
        let n = Double(min(max(people, 1), maxPeople))
        let tip = (bill * tipPercent / 100).rounded()
        let total = bill + tip
        return Result(tip: tip, total: total, perPerson: (total / n).rounded(.up))
    }
}

/// Einheiten, die auf Reisen im Weg stehen (Wetter, Strecke, Gepäck).
enum UnitConvert {
    enum Kind: String, CaseIterable, Identifiable {
        case temperature, distance, weight
        var id: String { rawValue }
        var textKey: String { "trv_unit_" + rawValue }
        var metric: String { self == .temperature ? "°C" : self == .distance ? "km" : "kg" }
        var imperial: String { self == .temperature ? "°F" : self == .distance ? "mi" : "lb" }
    }

    static func toImperial(_ v: Double, _ k: Kind) -> Double {
        switch k {
        case .temperature: return v * 9 / 5 + 32
        case .distance: return v * 0.621371
        case .weight: return v * 2.20462
        }
    }

    static func toMetric(_ v: Double, _ k: Kind) -> Double {
        switch k {
        case .temperature: return (v - 32) * 5 / 9
        case .distance: return v / 0.621371
        case .weight: return v / 2.20462
        }
    }

    /// „30 °C = 86 °F“ (eine Nachkommastelle, ohne unnötige Null); nil bei unsinniger Eingabe.
    static func line(_ v: Double, kind: Kind, toImperial imperial: Bool) -> String? {
        guard v.isFinite, abs(v) < 1e9 else { return nil }
        let out = imperial ? toImperial(v, kind) : toMetric(v, kind)
        let f = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
        let (a, b) = imperial ? (kind.metric, kind.imperial) : (kind.imperial, kind.metric)
        return "\(v.formatted(f)) \(a) = \(out.formatted(f)) \(b)"
    }
}

/// Uhrzeit auf Thai, wie man sie sagt (Sechs-Perioden-System): 14:30 = บ่ายสองโมงครึ่ง.
enum ThaiClock {
    static func spoken(hour: Int, minute: Int) -> String? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let h: String
        switch hour {
        case 0: h = "เที่ยงคืน"
        case 1...5: h = "ตี" + ThaiNumber.words(hour)!
        case 6...11: h = ThaiNumber.words(hour)! + "โมงเช้า"
        case 12: h = "เที่ยง"
        case 13: h = "บ่ายโมง"
        case 14, 15: h = "บ่าย" + ThaiNumber.words(hour - 12)! + "โมง"
        case 16...18: h = ThaiNumber.words(hour - 12)! + "โมงเย็น"
        default: h = ThaiNumber.words(hour - 18)! + "ทุ่ม"   // 19–23
        }
        switch minute {
        case 0: return h
        case 30: return h + "ครึ่ง"
        default: return h + ThaiNumber.words(minute)! + "นาที"
        }
    }
}

/// Telefonnummer Ziffer für Ziffer als Thai-Zahlwörter (Taxi, Hotel, Rezeption), Gruppen durch Leerzeichen getrennt.
enum PhoneDigits {
    private static let words = ["ศูนย์", "หนึ่ง", "สอง", "สาม", "สี่", "ห้า", "หก", "เจ็ด", "แปด", "เก้า"]
    static let maxDigits = 20

    /// Gruppen am Trenner (Leerzeichen, Strich, Klammer); Thai-Ziffern zählen mit. nil ohne Ziffern oder bei zu langer Eingabe.
    static func spoken(_ raw: String) -> String? {
        let s = PriceSpotter.asciiDigits(raw)
        var groups: [String] = [], cur: [String] = []
        var count = 0
        for ch in s {
            if let d = ch.wholeNumberValue, ch.isASCII {
                cur.append(words[d]); count += 1
            } else if !cur.isEmpty {
                groups.append(cur.joined(separator: " ")); cur = []
            }
        }
        if !cur.isEmpty { groups.append(cur.joined(separator: " ")) }
        guard count > 0, count <= maxDigits else { return nil }
        return groups.joined(separator: "  ")
    }
}

/// Export-Dateien (Verlauf als CSV) liegen im Temp-Ordner und enthalten Gesprächstext: nach dem Teilen nicht liegen lassen.
enum ExportCleanup {
    static func isExport(_ name: String) -> Bool { name.hasPrefix("Dolmetscher-") && name.hasSuffix(".csv") }

    /// Löscht alte Export-Dateien; gibt die Zahl der gelöschten zurück.
    @discardableResult
    static func purge(in dir: URL = URL.temporaryDirectory, fileManager fm: FileManager = .default) -> Int {
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        var n = 0
        for name in names where isExport(name) {
            if (try? fm.removeItem(at: dir.appending(path: name))) != nil { n += 1 }
        }
        return n
    }
}

extension View {
    /// VoiceOver liest `text` mit der Stimme von `locale` (z. B. „th-TH“) statt der Systemsprache.
    func spokenIn(_ locale: String, _ text: String) -> some View {
        accessibilityLabel(A11yLabel.text(NSAttributedString(string: text, attributes: [.accessibilitySpeechLanguage: locale])))
    }
}

/// Ansicht der Reise-Helfer.
struct TravelHelpersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bill = ""
    @State private var tip = 10.0
    @State private var people = 2
    @State private var unitKind = UnitConvert.Kind.temperature
    @State private var unitValue = ""
    @State private var toImperial = true
    @State private var time = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var phone = ""
    @State private var asking = ""

    private var thaiTime: String? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return ThaiClock.spoken(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    var body: some View {
        Form {
            Section(T("trv_tip_split")) {
                TextField("฿", text: $bill).keyboardType(.numbersAndPunctuation)
                Picker(T("trv_tip_pct"), selection: $tip) {
                    ForEach([0.0, 5, 10, 15], id: \.self) { Text("\(Int($0)) %").tag($0) }
                }
                .pickerStyle(.segmented)
                Stepper(String(format: T("trv_people"), people), value: $people, in: 1...BillSplit.maxPeople)
                if let a = AmountParser.parse(bill), let r = BillSplit.split(bill: a, tipPercent: tip, people: people) {
                    LabeledContent(T("trv_tip_amount")) { Text("฿\(Int(r.tip))").monospacedDigit() }
                    LabeledContent(T("trv_total")) { Text("฿\(Int(r.total))").monospacedDigit() }
                    LabeledContent(T("trv_per_person")) { Text("฿\(Int(r.perPerson))").bold().monospacedDigit() }
                }
            }
            Section(T("trv_units")) {
                Picker("", selection: $unitKind) {
                    ForEach(UnitConvert.Kind.allCases) { Text(T($0.textKey)).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(T("trv_to_imperial"), isOn: $toImperial)
                TextField("0", text: $unitValue).keyboardType(.numbersAndPunctuation)
                if let v = AmountParser.parse(unitValue) ?? Double(unitValue), let l = UnitConvert.line(v, kind: unitKind, toImperial: toImperial) {
                    Text(l).font(.title3.bold().monospacedDigit())
                }
            }
            Section(T("trv_time")) {
                DatePicker(T("trv_time"), selection: $time, displayedComponents: .hourAndMinute)
                if let t = thaiTime {
                    Text(t).font(.title2).spokenIn("th-TH", t)
                }
            }
            Section {
                TextField("฿", text: $asking).keyboardType(.numbersAndPunctuation)
                    .accessibilityLabel(T("trv_asking"))
                ForEach(AmountParser.parse(asking).map(Bargain.offers(asking:)) ?? []) { o in
                    HStack {
                        Text("\(o.percent) %").foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        Text("฿\(o.amount)").bold().monospacedDigit()
                        Text(o.words).font(.footnote).spokenIn("th-TH", o.words)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: { Text(T("trv_bargain")) }
            Section(T("trv_date")) {
                let written = ThaiDate.text(Date()), said = ThaiDate.text(Date(), spoken: true)
                Text(written).font(.title3).spokenIn("th-TH", said)
            }
            Section {
                TextField("081 234 5678", text: $phone).keyboardType(.phonePad)
                if let p = PhoneDigits.spoken(phone) {
                    Text(p).font(.title3).spokenIn("th-TH", p)
                }
            } header: { Text(T("trv_phone")) } footer: { Text(T("trv_phone_hint")) }
        }
        .navigationTitle(T("trv_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
