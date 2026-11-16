// Tools.swift – Reise-Werkzeuge: Notfallkarte (zum Zeigen, offline) und Baht-Rechner.
import SwiftUI

struct EmergencyInfo: Codable, Equatable {
    var name = ""
    var hotel = ""
    var allergies = ""
    var medical = ""
    var contact = ""
    var bloodType = ""
    var insurance = ""
    var embassy = ""
    /// Strukturierte Allergien (feste, geprüfte Sätze statt Freitext-Übersetzung).
    var allergens: [Allergen] = []
    /// Maschinelle Übersetzung der Freitexte in die Partnersprache: Feld -> Text.
    var translated: [String: String] = [:]
    var translatedLang: String?
    /// Stand der Freitexte bei der Übersetzung – geändert = Übersetzung veraltet.
    var translatedSource: String?

    init() {}

    /// Nachsichtig: ältere Karten ohne die neuen Felder dürfen nicht leer laden.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) .flatMap { $0 } ?? "" }
        name = s(.name); hotel = s(.hotel); allergies = s(.allergies); medical = s(.medical); contact = s(.contact)
        bloodType = s(.bloodType); insurance = s(.insurance); embassy = s(.embassy)
        // unbekannte Allergene (neuere Version) überspringen statt alles zu verwerfen
        let raw = (try? c.decodeIfPresent([String].self, forKey: .allergens)) .flatMap { $0 } ?? []
        allergens = raw.compactMap(Allergen.init(rawValue:))
        translated = (try? c.decodeIfPresent([String: String].self, forKey: .translated)) .flatMap { $0 } ?? [:]
        translatedLang = try? c.decodeIfPresent(String.self, forKey: .translatedLang)
        translatedSource = try? c.decodeIfPresent(String.self, forKey: .translatedSource)
    }

    /// Felder, die übersetzt werden (Name, Adresse, Nummern nicht).
    var translatable: [(String, String)] { [("allergies", allergies), ("medical", medical)] }
    var translatableHash: String { translatable.map(\.1).joined(separator: "\u{1F}") }

    /// Übersetzung passt zur Partnersprache und zum aktuellen Text?
    func translation(for field: String, lang: Lang) -> String? {
        guard translatedLang == lang.rawValue, translatedSource == translatableHash else { return nil }
        return translated[field]
    }

    var needsTranslation: Bool { translatable.contains { !$0.1.isEmpty } }

    var isEmpty: Bool {
        [name, hotel, allergies, medical, contact, bloodType, insurance, embassy].allSatisfy(\.isEmpty) && allergens.isEmpty
    }
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
    @State private var showAllergy = false
    @State private var translating = false

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

                allergySection
                Section {
                    if editing {
                        TextField(T("em_name"), text: $m.emergency.name)
                        TextField(T("em_hotel"), text: $m.emergency.hotel, axis: .vertical)
                        TextField(T("em_allergies"), text: $m.emergency.allergies, axis: .vertical)
                        TextField(T("em_medical"), text: $m.emergency.medical, axis: .vertical)
                        TextField(T("em_blood"), text: $m.emergency.bloodType)
                        TextField(T("em_insurance"), text: $m.emergency.insurance, axis: .vertical)
                        TextField(T("em_embassy"), text: $m.emergency.embassy, axis: .vertical)
                        TextField(T("em_contact"), text: $m.emergency.contact)
                    } else if m.emergency.isEmpty || !hasCardText {
                        Text(T("em_empty")).foregroundStyle(.secondary)
                    } else {
                        card
                        if m.emergency.needsTranslation && !translated {
                            Button {
                                Task { translating = true; await m.translateEmergency(); translating = false }
                            } label: {
                                HStack {
                                    Label(String(format: T("em_translate"), m.pair.partner.name(in: L10n.lang)), systemImage: "character.bubble")
                                    if translating { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(translating)
                        }
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
            .fullScreenCover(isPresented: $showAllergy) { AllergyCardView() }
        }
    }

    private func allergen(_ a: Allergen) -> Binding<Bool> {
        Binding(get: { m.emergency.allergens.contains(a) },
                set: { on in
                    var set = Set(m.emergency.allergens)
                    if on { set.insert(a) } else { set.remove(a) }
                    m.emergency.allergens = Allergen.allCases.filter(set.contains)   // feste Reihenfolge
                })
    }

    private var allergySection: some View {
        let ui: Lang = L10n.asLang ?? .en
        let partner: String = m.pair.partner.name(in: L10n.lang)
        return Section {
            ForEach(Allergen.allCases, id: \.self) { (a: Allergen) in
                Toggle(a.name(ui) ?? a.name(.en) ?? a.rawValue, isOn: allergen(a))
            }
            Button { showAllergy = true } label: {
                Label(String(format: T("allergy_show"), partner), systemImage: "allergens").font(.headline)
            }
            .disabled(m.emergency.allergens.isEmpty)
        } header: { Text(T("allergy_card")) } footer: { Text(T("allergy_note")) }
    }

    private var hasCardText: Bool {
        let e = m.emergency
        return ![e.name, e.hotel, e.allergies, e.medical, e.contact, e.bloodType, e.insurance, e.embassy].allSatisfy(\.isEmpty)
    }

    private var translated: Bool {
        m.emergency.translatable.allSatisfy { $0.1.isEmpty || m.emergency.translation(for: $0.0, lang: m.pair.partner) != nil }
    }

    /// Karte zum Zeigen: Überschriften in der Partnersprache (soweit die Oberfläche sie kennt, sonst Englisch)
    /// plus eigene Sprache; Freitexte zusätzlich maschinell übersetzt, deutlich gekennzeichnet.
    private var card: some View {
        let e = m.emergency
        return VStack(alignment: .leading, spacing: 10) {
            row("em_name", e.name)
            row("em_hotel", e.hotel)
            row("em_allergies", e.allergies, field: "allergies")
            row("em_medical", e.medical, field: "medical")
            row("em_blood", e.bloodType)
            row("em_insurance", e.insurance)
            row("em_embassy", e.embassy)
            row("em_contact", e.contact)
        }
        .padding(.vertical, 6)
    }

    private func title(_ key: String) -> String {
        let partner = L10n.text(key, lang: L10n.uiCode(m.pair.partner)) ?? L10n.table[key]?["en"] ?? key
        let mine = T(key)
        return partner == mine ? partner : "\(partner) · \(mine)"
    }

    @ViewBuilder private func row(_ key: String, _ value: String, field: String? = nil) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(key)).font(.caption).foregroundStyle(.secondary)
                if let field, let t = m.emergency.translation(for: field, lang: m.pair.partner), t != value {
                    Text(t).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text(value).font(.subheadline).foregroundStyle(.secondary)
                    Label(T("machine_translated"), systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                } else {
                    Text(value).font(.title3.weight(.semibold)).textSelection(.enabled)
                }
            }
        }
    }
}

/// Allergie-Karte bildschirmfüllend zum Zeigen (Restaurant, Garküche). Feste Sätze in der Partnersprache;
/// ist die Sprache nicht hinterlegt: Englisch plus maschinelle Übersetzung (gekennzeichnet).
struct AllergyCardView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var flipped = false
    @State private var machine: String?

    var body: some View {
        let partner = m.pair.partner
        let list = m.emergency.allergens
        let fixed = Allergen.card(list, in: partner, politeness: m.politeness)
        let english = Allergen.card(list, in: .en)
        let mineLang = L10n.asLang.flatMap { Allergen.isCurated($0) ? $0 : nil } ?? .en
        let mine = Allergen.card(list, in: mineLang, politeness: m.politeness)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("⚠️", systemImage: "allergens").labelStyle(.iconOnly).font(.system(size: 54)).foregroundStyle(.red)
                    if let fixed {
                        Text(fixed.title).font(.system(size: 40, weight: .heavy)).foregroundStyle(.red)
                        Text(fixed.warning).font(.title2.weight(.semibold))
                    } else {
                        if let machine {
                            Text(machine).font(.system(size: 34, weight: .heavy)).foregroundStyle(.red)
                            Label(T("machine_translated"), systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                        }
                        if let english {
                            Text(english.title).font(.title.bold())
                            Text(english.warning).font(.title3)
                        }
                    }
                    if let mine, mineLang != partner, !(fixed == nil && mineLang == .en) {
                        Divider()
                        Text(mine.title + " " + mine.warning).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .rotationEffect(.degrees(flipped ? 180 : 0))
            Divider()
            HStack(spacing: 28) {
                Button { flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel(T("flip"))
                Button {
                    if let fixed { m.announce(fixed.title + " " + fixed.warning, lang: partner) }
                    else if let machine { m.announce(machine, lang: partner) }
                } label: { Image(systemName: "speaker.wave.2.fill") }
                    .accessibilityLabel(T("replay"))
                Spacer()
                Button(T("done")) { dismiss() }
            }
            .font(.title2)
            .padding()
        }
        .persistentSystemOverlays(.hidden)
        .task {
            guard fixed == nil, let english else { return }
            machine = await m.translateText(english.title + " " + english.warning, from: .en, to: partner)
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
