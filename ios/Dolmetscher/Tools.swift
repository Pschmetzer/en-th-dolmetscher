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
        ("1193", "Highway police", "ตำรวจทางหลวง", "car.fill"),
        ("1672", "Tourist hotline (TAT)", "สายด่วนการท่องเที่ยว (ททท.)", "info.circle.fill"),
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
                if m.features.thaiExtras { thaiSections }

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
                                    if translating { Spacer(); ProgressView().accessibilityLabel(T("translating")) }
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
            .doneToolbar { dismiss() }
            .fullScreenCover(isPresented: $showAllergy) { AllergyCardView() }
        }
    }

    /// Hilfe-Bildschirm und Notrufnummern (nur mit Thai im Paar).
    @ViewBuilder private var thaiSections: some View {
        Section {
            Button { m.sheet = .helpNow } label: {
                Label(T("help_now"), systemImage: "sos").font(.headline).foregroundStyle(StatusColor.error)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        Section {
            ForEach(ThaiEmergency.numbers, id: \.number) { n in DialRow(number: n.number, en: n.en, th: n.th, icon: n.icon) }
        } header: { Text(T("emergency_numbers")) }
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
                    Label(T("machine_translated"), systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(StatusColor.warning)
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
    @ScaledMetric(relativeTo: .largeTitle) private var scaled34: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var scaled40: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var scaled54: CGFloat = 54
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
                    Label("⚠️", systemImage: "allergens").labelStyle(.iconOnly).font(.system(size: scaled54)).foregroundStyle(StatusColor.error)
                    if let fixed {
                        Text(fixed.title).font(.system(size: scaled40, weight: .heavy)).foregroundStyle(StatusColor.error)
                        Text(fixed.warning).font(.title2.weight(.semibold))
                    } else {
                        if let machine {
                            Text(machine).font(.system(size: scaled34, weight: .heavy)).foregroundStyle(StatusColor.error)
                            Label(T("machine_translated"), systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(StatusColor.warning)
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
                Button { flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down").minTapTarget() }
                    .accessibilityLabel(T("flip"))
                Button {
                    if let fixed { m.announce(fixed.title + " " + fixed.warning, lang: partner) }
                    else if let machine { m.announce(machine, lang: partner) }
                } label: { Image(systemName: "speaker.wave.2.fill").minTapTarget() }
                    .accessibilityLabel(T("replay"))
                Spacer()
                Button(T("done")) { dismiss() }
            }
            .font(.title2)
            .padding()
        }
        .persistentSystemOverlays(.hidden)
        .modifier(FullBrightness())
        .task {
            guard fixed == nil, let english else { return }
            machine = await m.translateText(english.title + " " + english.warning, from: .en, to: partner)
        }
    }
}

/// Startwerte des Baht-Rechners nach Währung der Region des Geräts (ungefähre Kurse, der Nutzer trägt seinen eigenen ein).
enum FXDefaults {
    /// 1 THB in der Währung – grobe Richtwerte, nur als Vorbelegung.
    static let rates: [String: Double] = [
        "EUR": 0.026, "USD": 0.028, "GBP": 0.022, "CHF": 0.025, "JPY": 4.3, "CNY": 0.2, "KRW": 40,
        "AUD": 0.043, "CAD": 0.039, "SGD": 0.037, "INR": 2.5, "VND": 700, "IDR": 480, "RUB": 2.6,
    ]

    static func code(for locale: Locale = .current) -> String {
        if let c = locale.currency?.identifier, rates[c] != nil { return c }
        return "EUR"
    }

    static func rate(for code: String) -> Double { rates[code] ?? 0.026 }
}

/// Einfacher Rechner Baht ⇄ eigene Währung mit selbst eingetragenem Kurs (kein Netz nötig).
struct BahtCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var codeWidth: CGFloat = 56
    @State private var showPrice = false
    @AppStorage("fxRate") private var rate = FXDefaults.rate(for: FXDefaults.code())   // 1 THB in Heimatwährung
    @AppStorage("fxCode") private var code = FXDefaults.code()
    @State private var baht = ""
    @FocusState private var focused: Bool
    /// Kurs holen: nur auf Wunsch (Frankfurter/EZB). Ohne Netz bleibt der letzte Wert.
    @AppStorage("fxAuto") private var fxAuto = false
    @AppStorage("fxDate") private var fxDate = ""
    @State private var fxBusy = false

    private func fetchRate() async {
        guard fxAuto, code.count == 3, let url = FXFetch.url(code: code) else { return }
        fxBusy = true
        defer { fxBusy = false }
        var req = URLRequest(url: url); req.timeoutInterval = 6
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              OnlineStatus.of(resp) == .ok, let r = FXFetch.parse(data, code: code) else { return }
        rate = r.rate
        fxDate = r.date
    }

    /// „1,200“ = 1200 (Tausender-Komma wie auf Thai-Preisschildern), „12,5“ = 12.5.
    private var amount: Double? { AmountParser.parse(baht) }

    /// Im Währungsformat der Oberflächensprache (Komma, Symbol-Stellung); unbekannter Code: Zahl plus Code.
    private func home(_ thb: Double) -> String {
        let v = thb * rate
        guard code.count == 3 else { return String(format: "%.2f %@", v, code) }
        return v.formatted(.currency(code: code.uppercased()).locale(Locale(identifier: L10n.lang)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("฿", text: $baht)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.largeTitle.monospacedDigit())
                        .focused($focused)
                    if let a = amount {
                        Text("≈ " + home(a))
                            .font(.title.bold().monospacedDigit())
                            .foregroundStyle(StatusColor.info)
                        if a >= 1, a < 1_000_000_000, let w = ThaiNumber.words(Int(a)) {
                            Text(w + "บาท").font(.title3).foregroundStyle(StatusColor.warning)
                        }
                        Button { showPrice = true } label: { Label(T("price_show"), systemImage: "rectangle.expand.vertical") }
                            .disabled(a < 1 || a >= 1_000_000_000)
                    }
                } header: { Text(T("baht_amount")) }

                Section {
                    HStack {
                        Text("1 THB =")
                        TextField("0.026", value: $rate, format: .number.precision(.fractionLength(2...5)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        TextField("EUR", text: $code)
                            .frame(minWidth: codeWidth)
                            .textInputAutocapitalization(.characters)
                    }
                    ForEach([20.0, 50, 100, 500, 1000], id: \.self) { b in
                        HStack {
                            Text("฿ \(Int(b))").monospacedDigit()
                            Spacer()
                            Text(home(b)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Toggle(T("fx_auto"), isOn: $fxAuto)
                    if fxAuto {
                        HStack {
                            if fxBusy { ProgressView() }
                            Text(fxDate.isEmpty ? T("fx_manual") : String(format: T("fx_rate_date"), fxDate))
                                .font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Button(T("retry")) { Task { await fetchRate() } }.buttonStyle(.borderless)
                        }
                    }
                } header: { Text(T("baht_rate")) } footer: { Text(T("baht_note")) }
            }
            .navigationTitle(T("baht_calc"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .onAppear { focused = true }
            .task(id: fxAuto) { await fetchRate() }
            .fullScreenCover(isPresented: $showPrice) {
                PriceShowView(amount: Int(amount ?? 0), home: amount.map(home))
            }
        }
    }
}
