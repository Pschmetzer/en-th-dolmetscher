// Round4Views.swift – Ansichten der Runde 4: Reise-Vorbereitung, Ziele für Taxi/Tuk-Tuk, Notfall-Bildschirm mit
// Standort, Preis zeigen, Preis-Hinweis in der Blase, Werkzeug-Spalte fürs iPad.
import AVFoundation
import CoreLocation
import PhotosUI
import SwiftUI
import Translation

// MARK: Werkzeug-Spalte (iPad) und „Fertig“-Knopf

extension EnvironmentValues {
    /// Ansicht steckt in der Werkzeug-Spalte (iPad) statt in einem Sheet: kein „Fertig“-Knopf.
    @Entry var inPanel = false
}

struct DoneToolbar: ViewModifier {
    @Environment(\.inPanel) private var inPanel
    let action: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            if !inPanel { ToolbarItem(placement: .confirmationAction) { Button(T("done"), action: action) } }
        }
    }
}

extension View {
    func doneToolbar(_ action: @escaping () -> Void) -> some View { modifier(DoneToolbar(action: action)) }
}

/// iPad: rechte Spalte mit Satzbuch, Zielen, Notfall und Baht-Rechner neben dem Gespräch.
struct ToolsPanel: View {
    @Environment(InterpreterModel.self) private var m
    @State private var tool = "phrasebook"

    private struct Tool: Identifiable {
        var id: String
        var icon: String
    }

    private var tools: [Tool] {
        var t: [Tool] = [Tool(id: "phrasebook", icon: "book"), Tool(id: "places", icon: "mappin.and.ellipse"),
                         Tool(id: "emergency", icon: "cross.case"), Tool(id: "learn", icon: "rectangle.stack")]
        if m.features.thaiExtras { t.append(Tool(id: "baht_calc", icon: "bahtsign.circle")) }
        return t
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(T("tools"), selection: $tool) {
                ForEach(tools) { (t: Tool) in Image(systemName: t.icon).accessibilityLabel(T(t.id)).tag(t.id) }
            }
            .pickerStyle(.segmented)
            .padding(10)
            content.environment(\.inPanel, true)
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder private var content: some View {
        switch tool {
        case "places": PlacesView()
        case "learn": LearnView()
        case "emergency": EmergencyView()
        case "baht_calc": BahtCalculatorView()
        default: PhrasebookView()
        }
    }
}

// MARK: Reise-Vorbereitung (535, 536)

struct TravelPrepView: View {
    var body: some View { NavigationStack { TravelPrepList() } }
}

struct TravelPrepList: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var report = ReadinessReport()
    @State private var checked = false
    @State private var download: TranslationSession.Configuration?

    var body: some View {
            List {
                Section {
                    Text(T("prep_intro")).fixedSize(horizontal: false, vertical: true)
                    Label(T("prep_wifi"), systemImage: "wifi").foregroundStyle(.secondary)
                }
                Section(T("prep_steps")) {
                    PrepRow(ok: report.ok(.permission), checked: checked, title: T("prep_mic"), detail: T("prep_mic_d")) {
                        Button(T("prep_allow")) { Task { _ = await AVAudioApplication.requestRecordPermission(); await refresh() } }
                    }
                    PrepRow(ok: report.ok(.recognizer), checked: checked, title: T("prep_speech"), detail: T("prep_speech_d")) {
                        Button(T("prep_load")) { m.sheet = nil; m.start() }
                    }
                    PrepRow(ok: report.ok(.translation), checked: checked, title: T("prep_translate"), detail: T("prep_translate_d")) {
                        Button(T("prep_load")) { requestPacks() }
                    }
                    PrepRow(ok: report.ok(.voice), checked: checked, title: T("prep_voice"), detail: T("prep_voice_d")) {
                        EmptyView()
                    }
                }
                Section {
                    Button { m.sheet = nil; m.submit(T("example_sentence")) } label: {
                        Label(T("prep_try"), systemImage: "text.bubble")
                    }
                } footer: { Text(report.allReady ? T("prep_all_ok") : T("prep_footer")) }
            }
            .navigationTitle(T("prep_title"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .refreshable { await refresh() }
            .task { await refresh() }
            .translationTask(download) { session in
                try? await session.prepareTranslation()
                await refresh()
                await m.refreshOffline()
            }
    }

    private func requestPacks() {
        if download == nil {
            download = .init(source: Translator.language(m.pair.mine), target: Translator.language(m.pair.partner))
        } else {
            download?.invalidate()
        }
    }

    private func refresh() async {
        let p = m.pair
        var r = ReadinessReport()
        r.recognizerMine = await LangCheck.recognizer(p.mine)
        r.recognizerPartner = await LangCheck.recognizer(p.partner)
        let a = await LangCheck.translation(p.mine, p.partner)
        let b = await LangCheck.translation(p.partner, p.mine)
        r.translation = ReadinessReport.combine(a, b)
        r.voiceMine = Speaker.hasVoice(p.mine)
        r.voicePartner = Speaker.hasVoice(p.partner)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: r.micAllowed = true
        case .denied: r.micAllowed = false
        default: r.micAllowed = nil
        }
        report = r
        checked = true
    }
}

private struct PrepRow<Action: View>: View {
    let ok: Bool
    let checked: Bool
    let title: String
    let detail: String
    @ViewBuilder var action: () -> Action

    private var icon: String { ok ? "checkmark.circle.fill" : "circle.dashed" }
    private var tint: Color { ok ? .green : .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                if checked && !ok { action().buttonStyle(.bordered).controlSize(.small) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(ok ? T("prep_ok") : T("prep_missing"))
    }
}

// MARK: Ziele für Taxi und Tuk-Tuk (547)

struct PlacesView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var local = ""
    @State private var shown: Place?
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var scanning = false
    @State private var scanError: String?

    var body: some View {
        NavigationStack {
            List {
                if m.places.isEmpty {
                    Text(T("places_empty")).foregroundStyle(.secondary)
                }
                ForEach(m.places) { p in
                    Button { shown = p } label: { PlaceRow(place: p) }
                        .buttonStyle(.plain)
                }
                .onDelete { m.places.remove(atOffsets: $0) }
                Section {
                    TextField(T("places_name"), text: $name)
                    TextField(T("places_local"), text: $local, axis: .vertical)
                    scanRow
                    Button(T("places_save"), action: add).disabled(name.isEmpty && local.isEmpty)
                } header: { Text(T("places_add")) } footer: {
                    if let scanError { Text("⚠️ " + scanError) } else { Text(T("places_scan_note")) }
                }
            }
            .navigationTitle(T("places"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .fullScreenCover(item: $shown) { p in PlaceBigView(place: p) }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { img in Task { await scan(img) } }.ignoresSafeArea()
            }
            .onChange(of: photo) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: data) { await scan(img) }
                    photo = nil
                }
            }
        }
    }

    /// Visitenkarte oder Schild abfotografieren: Text auf dem Gerät erkennen und in die Felder übernehmen.
    private var scanRow: some View {
        HStack {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { camera = true } label: { Label(T("places_scan"), systemImage: "camera.viewfinder") }
                Spacer()
            }
            PhotosPicker(selection: $photo, matching: .images) { Label(T("choose_photo"), systemImage: "photo") }
            if scanning { ProgressView().padding(.leading, 6) }
        }
        .buttonStyle(.borderless)
    }

    private func scan(_ img: UIImage) async {
        scanning = true; scanError = nil
        defer { scanning = false }
        do {
            let lines = try await TextScanner.lines(in: img, langs: [m.pair.partner, m.pair.mine])
            let found = PlaceScan.split(lines, local: m.pair.partner)
            if found.name.isEmpty && found.local.isEmpty { scanError = T("no_text"); return }
            if name.isEmpty { name = found.name }
            if !found.local.isEmpty { local = found.local }
            Haptics.success()
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func add() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = local.trimmingCharacters(in: .whitespacesAndNewlines)
        m.places.append(Place(name: n.isEmpty ? l : n, local: l))
        name = ""; local = ""
        Haptics.success()
    }
}

private struct PlaceRow: View {
    let place: Place
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(place.name).font(.headline)
            if !place.local.isEmpty && place.local != place.name {
                Text(place.local).font(.subheadline).foregroundStyle(LangStyle.partnerColor)
            }
        }
    }
}

/// Ziel bildschirmfüllend: „Bitte bringen Sie mich hierhin“ plus Name/Adresse in der Landessprache.
struct PlaceBigView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var scaled54: CGFloat = 54
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    let place: Place
    @State private var flipped = false

    private var thaiSentence: String? { m.pair.partner == .th ? Place.takeMeThai(m.politeness) : nil }
    private var shownName: String { place.local.isEmpty ? place.name : place.local }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                if let thaiSentence { Text(thaiSentence).font(.title.bold()).multilineTextAlignment(.center) }
                Text(shownName)
                    .font(.system(size: scaled54, weight: .heavy))
                    .minimumScaleFactor(0.3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                if shownName != place.name { Text(place.name).font(.title3).foregroundStyle(.secondary) }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotationEffect(.degrees(flipped ? 180 : 0))
            Divider()
            HStack(spacing: 28) {
                Button { flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel(T("flip"))
                Button(action: speak) { Image(systemName: "speaker.wave.2.fill") }
                    .accessibilityLabel(T("replay"))
                if let url = place.mapsURL {
                    Link(destination: url) { Image(systemName: "map") }.accessibilityLabel(T("places_maps"))
                }
                Spacer()
                Button(T("done")) { dismiss() }
            }
            .font(.title2)
            .padding()
        }
        .persistentSystemOverlays(.hidden)
        .modifier(FullBrightness())
    }

    private func speak() {
        let text = [thaiSentence, place.local.isEmpty ? nil : place.local].compactMap { $0 }.joined(separator: " ")
        if !text.isEmpty { m.announce(text, lang: m.pair.partner) }
    }
}

/// Zentrale Helligkeitsverwaltung: Mit mehreren Vollbild-Ansichten nacheinander (Großansicht, Hilfe jetzt) darf der
/// erhöhte Wert nie als „vorher“ gemerkt werden. Der Zähler merkt den Ausgangswert nur beim ersten Zugriff.
@MainActor
final class BrightnessKeeper {
    static let shared = BrightnessKeeper()
    private var holders = 0
    private var original: CGFloat?
    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen
    }

    func acquire() {
        holders += 1
        guard holders == 1, let s = screen else { return }
        original = s.brightness
        s.brightness = 1
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0, let o = original else { return }
        screen?.brightness = o
        original = nil
    }
}

/// Helligkeit auf Maximum, solange gezeigt wird (Sonne, Markt) – danach zurück.
struct FullBrightness: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { BrightnessKeeper.shared.acquire() }
            .onDisappear { BrightnessKeeper.shared.release() }
    }
}

// MARK: Notfall-Bildschirm (546)

@MainActor @Observable
final class LocationFinder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var location: CLLocation?
    var denied = false
    /// Keine Position bekommen (Fehler oder Zeitüberschreitung) – die Ansicht bietet „Nochmal“ an.
    var failed = false
    /// „Genauen Standort“ ist aus: Koordinaten können Kilometer danebenliegen.
    var approximate: Bool { manager.accuracyAuthorization == .reducedAccuracy }
    private var timeout: Task<Void, Never>?
    static let timeoutSeconds = 15.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func locate() {
        failed = false
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: denied = true
        default: request()
        }
    }

    private func request() {
        manager.requestLocation()
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.timeoutSeconds))
            guard !Task.isCancelled, let self, self.location == nil else { return }
            self.failed = true
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.denied = status == .denied || status == .restricted
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.request() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let l = locations.last
        Task { @MainActor in self.location = l; self.failed = false; self.timeout?.cancel() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in if self.location == nil { self.failed = true } }
    }

    /// „13.75630, 100.50180“ – so liest es jeder Helfer und jede Karten-App.
    static func text(_ l: CLLocation) -> String {
        String(format: "%.5f, %.5f", l.coordinate.latitude, l.coordinate.longitude)
    }
}

/// Ein Schirm für den Notfall: großer Hilfe-Satz, Hotel-Adresse, eigener Standort, Direktwahl.
struct HelpNowView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var scaled40: CGFloat = 40
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var finder = LocationFinder()

    private var helpThai: String { m.politeness.fill("ช่วยด้วย{p} {i}ต้องการความช่วยเหลือ{p}") }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(helpThai).font(.system(size: scaled40, weight: .heavy)).foregroundStyle(.red)
                    Text(T("help_need")).font(.title3).foregroundStyle(.secondary)
                    Button { m.announce(helpThai, lang: .th) } label: { Label(T("replay"), systemImage: "speaker.wave.3.fill") }
                }
                if !m.emergency.hotel.isEmpty {
                    Section(T("em_hotel")) { Text(m.emergency.hotel).font(.title3.weight(.semibold)).textSelection(.enabled) }
                }
                Section(T("help_location")) { locationRow }
                Section(T("emergency_numbers")) {
                    ForEach(ThaiEmergency.numbers, id: \.number) { n in DialRow(number: n.number, en: n.en, th: n.th, icon: n.icon) }
                }
            }
            .navigationTitle(T("help_now"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .onAppear { finder.locate() }
        }
        .modifier(FullBrightness())
    }

    @ViewBuilder private var locationRow: some View {
        if let l = finder.location {
            Text(LocationFinder.text(l)).font(.title2.monospacedDigit().bold()).textSelection(.enabled)
            Text(String(format: T("help_accuracy"), Int(l.horizontalAccuracy))).font(.footnote).foregroundStyle(.secondary)
            if let url = URL(string: String(format: "https://maps.apple.com/?ll=%.5f,%.5f&q=%.5f,%.5f", l.coordinate.latitude, l.coordinate.longitude,
                                            l.coordinate.latitude, l.coordinate.longitude)) {
                ShareLink(item: url) { Label(T("share_location"), systemImage: "square.and.arrow.up") }
            }
            if finder.approximate {
                Text(T("help_location_approx")).font(.footnote).foregroundStyle(.orange)
            }
        } else if finder.denied {
            Text(T("help_location_denied")).foregroundStyle(.secondary)
        } else if finder.failed {
            Text(T("help_location_failed")).foregroundStyle(.secondary)
            Button(T("retry")) { finder.locate() }
        } else {
            HStack { ProgressView(); Text(T("help_locating")).foregroundStyle(.secondary) }
        }
    }
}

struct DialRow: View {
    let number: String, en: String, th: String, icon: String
    var body: some View {
        if let url = URL(string: "tel:\(number)") {
            Link(destination: url) {
                HStack(spacing: 14) {
                    Image(systemName: icon).foregroundStyle(.red).frame(width: 28)
                    VStack(alignment: .leading) {
                        Text(en).font(.headline)
                        Text(th).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(number).font(.title2.monospacedDigit().bold())
                }
            }
            .accessibilityLabel("\(en), \(number)")
        }
    }
}

// MARK: Preis zeigen (541) und Preis-Hinweis (542, 543)

/// Betrag groß zum Zeigen beim Handeln: Ziffern, Thai-Zahlwort, Heimatwährung; vorlesbar.
struct PriceShowView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var scaled80: CGFloat = 80
    @ScaledMetric(relativeTo: .largeTitle) private var scaled40: CGFloat = 40
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    let amount: Int
    let home: String?
    @State private var flipped = false

    private var words: String { (ThaiNumber.words(amount) ?? "") + "บาท" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text("฿ " + amount.formatted()).font(.system(size: scaled80, weight: .heavy).monospacedDigit()).minimumScaleFactor(0.3)
                Text(words).font(.system(size: scaled40, weight: .bold)).foregroundStyle(LangStyle.partnerColor).minimumScaleFactor(0.3)
                if let home { Text("≈ " + home).font(.title2).foregroundStyle(.secondary) }
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotationEffect(.degrees(flipped ? 180 : 0))
            Divider()
            HStack(spacing: 28) {
                Button { flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel(T("flip"))
                Button { m.announce(words, lang: .th) } label: { Image(systemName: "speaker.wave.2.fill") }
                    .accessibilityLabel(T("replay"))
                Spacer()
                Button(T("done")) { dismiss() }
            }
            .font(.title2)
            .padding()
        }
        .persistentSystemOverlays(.hidden)
        .modifier(FullBrightness())
    }
}

/// Unter einer Blase: erkannte Baht-Beträge in Heimatwährung (aus dem Kurs des Baht-Rechners).
struct PriceLine: View {
    @AppStorage("fxRate") private var rate = 0.026
    @AppStorage("fxCode") private var code = "EUR"
    let text: String

    var body: some View {
        if let line = PriceSpotter.line(PriceSpotter.amounts(in: text), rate: rate, code: code, locale: Locale(identifier: L10n.lang)) {
            Label(line, systemImage: "bahtsign.circle")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: Foto-Text: Speisen-Lexikon (549) und buddhistisches Jahr (596)

struct LineHints: View {
    let line: String

    var body: some View {
        let dishes = Dishes.find(line)
        let years = BuddhistYear.notes(in: line)
        if !dishes.isEmpty || !years.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(dishes, id: \.th) { d in DishLine(dish: d) }
                // Fehlt ein Hinweis, heißt das nicht „ohne Allergene“ – gerade bei Erdnuss und Meeresfrüchten.
                if !dishes.isEmpty { Text(T("dish_incomplete")).font(.caption2).foregroundStyle(.secondary) }
                ForEach(years, id: \.self) { y in
                    Label(T("buddhist_year") + " " + y, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct DishLine: View {
    let dish: Dish

    private var name: String { L10n.lang == "de" ? dish.de : dish.en }
    private var notes: String { dish.notes.map { T("dish_" + $0.rawValue) }.joined(separator: " · ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("🍲 \(name) (\(dish.roman))").font(.caption.weight(.semibold))
            if !dish.notes.isEmpty { Text(notes).font(.caption2).foregroundStyle(LangStyle.partnerColor) }
        }
    }
}
