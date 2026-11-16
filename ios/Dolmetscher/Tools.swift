// Tools.swift – Reise-Werkzeuge: Notfallkarte (zum Zeigen, offline) und Baht-Rechner.
import SwiftUI

struct EmergencyInfo: Codable, Equatable {
    var name = ""
    var hotel = ""
    var allergies = ""
    var medical = ""
    var contact = ""
}

/// Wichtige Notrufnummern in Thailand (landesweit, kostenlos).
enum ThaiEmergency {
    static let numbers: [(number: String, en: String, th: String, icon: String)] = [
        ("1669", "Ambulance / medical emergency", "รถพยาบาล / เจ็บป่วยฉุกเฉิน", "cross.case.fill"),
        ("1155", "Tourist police (English)", "ตำรวจท่องเที่ยว", "person.badge.shield.checkmark.fill"),
        ("191", "Police", "ตำรวจ", "shield.fill"),
        ("199", "Fire", "ดับเพลิง", "flame.fill"),
    ]
}

struct EmergencyView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        @Bindable var m = m
        NavigationStack {
            List {
                if m.features.thaiExtras {
                Section {
                    ForEach(ThaiEmergency.numbers, id: \.number) { n in
                        if let url = URL(string: "tel:\(n.number)") {
                            Link(destination: url) {
                                HStack(spacing: 14) {
                                    Image(systemName: n.icon).foregroundStyle(.red).frame(width: 28)
                                    VStack(alignment: .leading) {
                                        Text(n.en).font(.headline)
                                        Text(n.th).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(n.number).font(.title2.monospacedDigit().bold())
                                }
                            }
                            .accessibilityLabel("\(n.en), \(n.number)")
                        }
                    }
                } header: { Text(T("emergency_numbers")) }
                }

                Section {
                    if editing {
                        TextField(T("em_name"), text: $m.emergency.name)
                        TextField(T("em_hotel"), text: $m.emergency.hotel, axis: .vertical)
                        TextField(T("em_allergies"), text: $m.emergency.allergies, axis: .vertical)
                        TextField(T("em_medical"), text: $m.emergency.medical, axis: .vertical)
                        TextField(T("em_contact"), text: $m.emergency.contact)
                    } else if m.emergency == EmergencyInfo() {
                        Text(T("em_empty")).foregroundStyle(.secondary)
                    } else {
                        card
                    }
                } header: {
                    HStack {
                        Text(T("em_card"))
                        Spacer()
                        Button(editing ? T("done") : T("edit")) { editing.toggle() }.textCase(nil)
                    }
                } footer: { Text(T("em_note")) }
            }
            .navigationTitle(T("emergency"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { dismiss() } } }
        }
    }

    /// Karte zum Zeigen: mit Thai im Paar Thai-Überschriften (fest), sonst in der Sprache der Oberfläche.
    /// Inhalte so wie eingegeben.
    private var card: some View {
        let thai = m.features.thaiExtras
        return VStack(alignment: .leading, spacing: 10) {
            row(thai ? "ชื่อ · Name" : T("em_name"), m.emergency.name)
            row(thai ? "โรงแรม / ที่พัก · Hotel" : T("em_hotel"), m.emergency.hotel)
            row(thai ? "แพ้ · Allergies" : T("em_allergies"), m.emergency.allergies)
            row(thai ? "ข้อมูลทางการแพทย์ · Medical" : T("em_medical"), m.emergency.medical)
            row(thai ? "ติดต่อ · Contact" : T("em_contact"), m.emergency.contact)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func row(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold)).textSelection(.enabled)
            }
        }
    }
}

/// Einfacher Rechner Baht ⇄ eigene Währung mit selbst eingetragenem Kurs (kein Netz nötig).
struct BahtCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fxRate") private var rate = 0.026        // 1 THB in Heimatwährung
    @AppStorage("fxCode") private var code = "EUR"
    @State private var baht = ""
    @FocusState private var focused: Bool

    /// „1,200“ = 1200 (Tausender-Komma wie auf Thai-Preisschildern), „12,5“ = 12.5.
    private var amount: Double? { AmountParser.parse(baht) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("฿", text: $baht)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.largeTitle.monospacedDigit())
                        .focused($focused)
                    if let a = amount {
                        Text(String(format: "≈ %.2f %@", a * rate, code))
                            .font(.title.bold().monospacedDigit())
                            .foregroundStyle(.blue)
                    }
                } header: { Text(T("baht_amount")) }

                Section {
                    HStack {
                        Text("1 THB =")
                        TextField("0.026", value: $rate, format: .number.precision(.fractionLength(2...5)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        TextField("EUR", text: $code)
                            .frame(width: 56)
                            .textInputAutocapitalization(.characters)
                    }
                    ForEach([20.0, 50, 100, 500, 1000], id: \.self) { b in
                        HStack {
                            Text("฿ \(Int(b))").monospacedDigit()
                            Spacer()
                            Text(String(format: "%.2f %@", b * rate, code)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: { Text(T("baht_rate")) } footer: { Text(T("baht_note")) }
            }
            .navigationTitle(T("baht_calc"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { dismiss() } } }
            .onAppear { focused = true }
        }
    }
}
