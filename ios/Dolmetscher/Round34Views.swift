// Round34Views.swift – Runde 34: Oberflächen für die Reise-Bausteine der Runde 33: Speisekarten-Scan mit Allergen-Markierung,
// Reise-Modus-Karte, Offline-Ampel, Aussprache-Coach, Planer-Übersicht, Reise-Tagebuch, Hotelkarte als QR, Zwei-Geräte-Modus.
// Die Entscheidungen stehen in Round33.swift und Round34.swift (getestet); hier nur Darstellung und Ablauf.
import AVFoundation
import Observation
import PhotosUI
import SwiftUI

// MARK: Speisekarten-Scan

struct MenuScanView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var load: Task<Void, Never>?
    @State private var scanTask: Task<Void, Never>?
    @State private var lines: [String] = []
    @State private var busy = false
    @State private var error: String?
    @State private var camera = false
    @State private var onlyHits = false
    @ScaledMetric(relativeTo: .title) private var thumb: CGFloat = 200

    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var avoid: Set<String> { MenuScan.avoidIDs(m.emergency.allergens) }
    private var hits: [Int: MenuAllergens.Hit] { MenuScan.hitsByLine(lines, avoid: avoid) }
    private var uiLang: Lang { L10n.asLang ?? .en }
    @State private var image: UIImage?

    var body: some View {
        let hits = self.hits
        NavigationStack {
            List {
                Section {
                    if avoid.isEmpty {
                        Label(T("r34_menu_no_allergens"), systemImage: "info.circle").foregroundStyle(.secondary)
                        Button { m.sheet = .emergency } label: { Label(T("emergency"), systemImage: "cross.case") }
                    } else {
                        Label(MenuScan.names(Array(avoid.sorted()), in: uiLang), systemImage: "allergens")
                            .accessibilityLabel(T("r34_menu_avoiding") + ": " + MenuScan.names(Array(avoid.sorted()), in: uiLang))
                    }
                } header: { Text(T("r34_menu_avoiding")) }

                Section {
                    HStack {
                        if hasCamera {
                            Button { camera = true } label: { Label(T("take_photo"), systemImage: "camera") }
                            Spacer()
                        }
                        PhotosPicker(selection: $item, matching: .images) { Label(T("choose_photo"), systemImage: "photo.on.rectangle") }
                    }
                    .buttonStyle(.borderless)
                }
                if let image {
                    Section { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: thumb).frame(maxWidth: .infinity)
                        .accessibilityHidden(true) }
                }
                if busy {
                    Section {
                        HStack {
                            ProgressView(); Text(T("reading_text"))
                            Spacer()
                            Button(T("cancel")) { scanTask?.cancel(); scanTask = nil; busy = false }.buttonStyle(.borderless)
                        }
                    }
                }
                if let error { Section { Text("⚠️ " + error).foregroundStyle(StatusColor.error) } }
                if !lines.isEmpty {
                    Section {
                        Toggle(T("r34_menu_only"), isOn: $onlyHits)
                        Label(String(format: T("r34_menu_summary"), hits.count, lines.count),
                              systemImage: hits.isEmpty ? "checkmark.circle" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hits.isEmpty ? Color.secondary : StatusColor.warning)
                    }
                    Section {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            if !onlyHits || hits[i] != nil { row(line, hits[i]) }
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if hits.isEmpty, !avoid.isEmpty { Text(T("r34_menu_none")) }
                            Text(T("r34_menu_disclaimer"))
                        }
                    }
                }
            }
            .navigationTitle(T("r34_menu_title"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
            .onChange(of: item) { _, new in
                guard let new else { return }
                load?.cancel()
                load = Task {
                    if let data = try? await new.loadTransferable(type: Data.self), !Task.isCancelled,
                       let img = PhotoDownsample.image(from: data) { await scan(img) }
                    if item == new { item = nil }
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { img in Task { await scan(PhotoDownsample.image(img)) } }.ignoresSafeArea()
            }
        }
    }

    @ViewBuilder private func row(_ line: String, _ hit: MenuAllergens.Hit?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line)
            if let hit {
                if !hit.ids.isEmpty {
                    Label(String(format: T("r34_menu_hit"), MenuScan.names(hit.ids, in: uiLang)), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(StatusColor.error)
                }
                if !hit.maybe.isEmpty {
                    Label(String(format: T("r34_menu_maybe"), MenuScan.names(hit.maybe, in: uiLang)), systemImage: "questionmark.circle.fill")
                        .font(.footnote).foregroundStyle(StatusColor.warning)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func scan(_ img: UIImage) async {
        scanTask?.cancel()
        image = img
        busy = true; error = nil; lines = []
        let langs = [m.pair.partner, m.pair.mine]
        let t = Task {
            do {
                let found = try await TextScanner.lines(in: img, langs: langs)
                guard !Task.isCancelled else { return }
                lines = found
                if found.isEmpty { error = T("no_text") }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { busy = false }
        }
        scanTask = t
        await t.value
    }
}

// MARK: Reise-Modus-Karte

/// Vorschlag beim Start, wenn die Zeitzone auf ein anderes Land zeigt. Ändert nie von selbst: erst ein Tipp stellt die Sprache um.
struct TravelModeBanner: View {
    @Environment(InterpreterModel.self) private var m
    @AppStorage(TravelPrompt.key) private var dismissed = ""
    @AppStorage(TravelPrompt.enabledKey) private var enabled = true

    private var suggestion: TravelMode.Suggestion? {
        guard let region = TravelRegion.region(forZone: TimeZone.current.identifier) else { return nil }
        return TravelMode.suggest(region: region, home: Locale.current.region?.identifier, pair: m.pair)
    }

    var body: some View {
        if let s = suggestion, TravelPrompt.shouldShow(s, dismissed: dismissed, enabled: enabled) {
            let country = Locale(identifier: m.uiLang).localizedString(forRegionCode: s.region) ?? s.region
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Image(systemName: "airplane.arrival").foregroundStyle(.tint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: T("r34_travel_title"), country)).font(.subheadline.bold())
                        Text(String(format: T("r34_travel_emergency"), EmergencyNumbers.summary(s.emergency))).font(.caption)
                        if let c = s.currency { Text(String(format: T("r34_travel_currency"), c)).font(.caption) }
                    }
                    Spacer(minLength: 0)
                    Button { dismissed = s.region } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).minTapTarget() }
                        .accessibilityLabel(T("r34_travel_dismiss"))
                }
                if s.changesPair, let p = s.partner {
                    Button {
                        m.pair = LangPair(mine: m.pair.mine, partner: p)
                        dismissed = s.region
                    } label: { Text(String(format: T("r34_travel_switch"), "\(p.flag) \(p.native)")).font(.caption.bold()) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(10)
            .background(StatusColor.info.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: Offline-Ampel

struct ReadinessLightRow: View {
    let light: ReadinessLight
    let partnerVoice: VoiceQuality

    private var style: (icon: String, tint: Color) {
        switch light {
        case .green: return ("checkmark.circle.fill", StatusColor.ok)
        case .yellow: return ("exclamationmark.triangle.fill", StatusColor.warning)
        case .red: return ("xmark.octagon.fill", StatusColor.error)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(T(light.textKey), systemImage: style.icon).foregroundStyle(style.tint).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if partnerVoice < .enhanced, partnerVoice != .none {
                Text(T("r34_light_voice")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(T("r34_light_title") + ": " + T(light.textKey))
    }
}

// MARK: Aussprache-Coach

struct PronunciationCoachView: View {
    let card: LeitnerDeck.Card
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var heard = ""
    @State private var result: PronunciationCoach.Result?
    @State private var listening = false
    @State private var error: String?
    @State private var engine: AppleSpeechEngine?
    @State private var task: Task<Void, Never>?
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(card.back).font(.largeTitle.bold()).multilineTextAlignment(.center).minimumScaleFactor(0.5)
                    .accessibilityLabel(A11yLabel.spoken(card.back, card.lang))
                if let r = card.roman, !r.isEmpty { Text(r).font(.title3).italic().foregroundStyle(.secondary) }
                Button { m.announceCard(card) } label: { Image(systemName: "speaker.wave.2.fill").font(.title).minTapTarget() }
                    .accessibilityLabel(T("replay"))
                Spacer(minLength: 8)
                if let error { Text("⚠️ " + error).foregroundStyle(StatusColor.error).multilineTextAlignment(.center) }
                if listening {
                    Label(T("r34_coach_busy"), systemImage: "waveform").font(.headline)
                }
                if !heard.isEmpty { Text(String(format: T("r34_coach_heard"), heard)).font(.title3).multilineTextAlignment(.center) }
                if let result { verdict(result) }
                Spacer(minLength: 8)
                Button { listening ? finish() : start() } label: {
                    Label(T(listening ? "r34_coach_stop" : (result == nil ? "r34_coach_start" : "r34_coach_again")),
                          systemImage: listening ? "stop.circle.fill" : "mic.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(m.phase == .listening)
                if m.phase == .listening { Text(T("r34_coach_busy_main")).font(.footnote).foregroundStyle(.secondary) }
                Text(T("r34_coach_note")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(T("r34_coach_title"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { finish(); dismiss() }
            .onDisappear { finish() }
        }
    }

    @ViewBuilder private func verdict(_ r: PronunciationCoach.Result) -> some View {
        let (icon, key, tint): (String, String, Color) = switch r.verdict {
        case .good: ("checkmark.circle.fill", "r34_coach_good", StatusColor.ok)
        case .close: ("exclamationmark.circle.fill", "r34_coach_close", StatusColor.warning)
        case .retry: ("arrow.counterclockwise.circle.fill", "r34_coach_retry", StatusColor.error)
        }
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: iconSize)).foregroundStyle(tint).accessibilityHidden(true)
            Text(T(key)).font(.title2.bold())
            Text(String(format: T("r34_coach_score"), r.score)).foregroundStyle(.secondary)
            if !r.missing.isEmpty { Text(String(format: T("r34_coach_missing"), r.missing.joined(separator: ", "))).font(.footnote) }
        }
        .accessibilityElement(children: .combine)
    }

    private func start() {
        guard m.phase != .listening, !listening else { return }
        result = nil; heard = ""; error = nil; listening = true
        let e = AppleSpeechEngine()
        engine = e
        let lang = card.lang
        task = Task {
            do {
                try await e.start(langs: [lang], pauseSeconds: 1.2, options: AudioOptions(), onDownload: { _, _ in })
                for await ev in e.events {
                    if Task.isCancelled { break }
                    switch ev {
                    case .partial(let d): if let t = d[lang]?.text, !t.isEmpty { heard = t }
                    case .utterance(let d):
                        if let t = d[lang]?.text {
                            heard = t
                            result = PronunciationCoach.score(expected: card.back, heard: t)
                            if result?.verdict == .good { Haptics.success() } else { Haptics.tap() }
                        }
                        await stopEngine()
                        return
                    case .failed(let msg): error = msg; await stopEngine(); return
                    default: break
                    }
                }
            } catch { self.error = error.localizedDescription }
            await stopEngine()
        }
    }

    private func finish() {
        task?.cancel(); task = nil
        Task { await stopEngine() }
    }

    private func stopEngine() async {
        let e = engine
        engine = nil
        listening = false
        await e?.stop()
    }
}

// MARK: Planer-Übersicht (Learn)

struct PlannerSummaryView: View {
    let forecast: PlannerStore.Forecast

    var body: some View {
        if forecast.tracked > 0 {
            VStack(spacing: 2) {
                Text(T("r34_plan_title")).font(.footnote.bold())
                Text(String(format: T("r34_plan_today"), forecast.dueNow) + " · " + String(format: T("r34_plan_week"), forecast.dueThisWeek))
                Text(String(format: T("r34_plan_recall"), forecast.recallPercent))
            }
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Orte als Auswahl in der Lernansicht: zeigt zuerst fällige Karten, die dort passen.
struct PlaceChips: View {
    @Binding var place: PlaceKind?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, T("r34_place_any"))
                ForEach(PlaceChoices.all, id: \.self) { p in chip(p, T(PlaceChoices.textKey(p))) }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(T("r34_place_title"))
    }

    private func chip(_ p: PlaceKind?, _ title: String) -> some View {
        Button { place = p } label: {
            Text(title).font(.footnote.weight(place == p ? .bold : .regular)).padding(.horizontal, 10).padding(.vertical, 8)
                .background(place == p ? StatusColor.info.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(place == p ? .isSelected : [])
    }
}

// MARK: Reise-Tagebuch

struct DiaryView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    var body: some View {
        NavigationStack {
            Group {
                if m.learnLocked {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill").font(.system(size: iconSize)).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(T("r34_diary_locked")).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button(T("lock_unlock")) { m.unlockHistory() }.buttonStyle(.borderedProminent)
                    }.padding()
                } else {
                    content(TravelDiary.summarize(m.visibleEntries))
                }
            }
            .navigationTitle(T("r34_diary_title"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
        }
    }

    @ViewBuilder private func content(_ s: TravelDiary.Summary) -> some View {
        if s.turns == 0 {
            VStack(spacing: 12) {
                Image(systemName: "book.closed").font(.system(size: iconSize)).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(T("r34_diary_empty")).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }.padding()
        } else {
            List {
                Section {
                    stat("text.bubble", String(format: T("r34_diary_turns"), s.turns))
                    stat("calendar", String(format: T("r34_diary_days"), s.days))
                    stat("flame", String(format: T("r34_diary_streak"), s.longestStreak))
                    stat("airplane", String(format: T("r34_diary_offline"), s.offlinePercent))
                    if let d = s.busiest {
                        stat("star", String(format: T("r34_diary_busiest"), d.formatted(date: .abbreviated, time: .omitted)))
                    }
                }
                Section(T("r34_diary_langs")) {
                    ForEach(s.perLang.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }, id: \.key) { code, n in
                        let l = Lang(rawValue: code)
                        HStack {
                            Text("\(l?.flag ?? "") \(l?.native ?? code)")
                            Spacer()
                            Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section { EmptyView() } footer: { Text(T("r34_diary_note")) }
            }
        }
    }

    private func stat(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
    }
}

// MARK: Hotelkarte als QR-Code

struct HotelQRView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @ScaledMetric(relativeTo: .largeTitle) private var qrSize: CGFloat = 260

    var body: some View {
        NavigationStack {
            let outcome = HotelCard.outcome(hotel: m.emergency.hotel, phone: phone)
            let parts = HotelCard.split(m.emergency.hotel)
            ScrollView {
                VStack(spacing: 16) {
                    switch outcome {
                    case .empty:
                        Label(T("r34_hotel_empty"), systemImage: "info.circle").foregroundStyle(.secondary)
                        Button { m.sheet = .emergency } label: { Label(T("emergency"), systemImage: "cross.case") }.buttonStyle(.bordered)
                    case .tooLong:
                        Label(T("r34_hotel_toolong"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(StatusColor.warning)
                    case .ready(let text):
                        if let img = QRImage.make(text) {
                            Image(uiImage: img).interpolation(.none).resizable().scaledToFit().frame(maxWidth: qrSize)
                                .padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel(T("r34_hotel_qr_a11y"))
                        }
                        Text(parts.name).font(.title2.bold()).multilineTextAlignment(.center)
                        if !parts.address.isEmpty { Text(parts.address).font(.title3).multilineTextAlignment(.center) }
                    }
                    TextField(T("r34_hotel_phone"), text: $phone).keyboardType(.phonePad).textFieldStyle(.roundedBorder)
                    Text(T("r34_hotel_hint")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle(T("r34_hotel_title"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { dismiss() }
        }
        .modifier(FullBrightness())
    }
}

// MARK: Zwei-Geräte-Modus

@MainActor @Observable
final class PairSession {
    struct Line: Identifiable, Equatable {
        let id = UUID()
        var mine: Bool
        var lang: Lang
        var text: String
        var translation: String?
    }
    struct Invite: Identifiable {
        let id = UUID()
        var from: String
        var answer: @Sendable (Bool) -> Void
    }

    private(set) var state = PeerState()
    private(set) var nearby: [String] = []
    private(set) var lines: [Line] = []
    var invite: Invite?
    @ObservationIgnored private var link: PeerLink?
    @ObservationIgnored weak var model: InterpreterModel?

    var running: Bool { link != nil }
    var myName: String { link?.myName ?? "" }

    func start() {
        guard link == nil else { return }
        let l = PeerLink()
        l.onEvent = { [weak self] e in Task { @MainActor in self?.handle(e) } }
        link = l
        state.startSearch()
        l.start()
    }

    func stop() {
        link?.onEvent = nil
        link?.stop()
        link = nil
        state.lost()
        nearby = []; invite = nil; lines = []
        state = PeerState()
    }

    func connect(_ name: String) { link?.invite(name) }

    func send(_ text: String, lang: Lang) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, case .connected = state.phase else { return }
        let msg = PeerMessage.text(t, lang: lang)
        guard msg.encode() != nil else { return }
        _ = state.accept(msg)   // eigene Nachricht gilt als gesehen
        link?.send(msg)
        lines.append(Line(mine: true, lang: lang, text: t))
    }

    private func handle(_ e: PeerLink.Event) {
        switch e {
        case .found(let n): if !nearby.contains(n) { nearby.append(n) }
        case .lost(let n): nearby.removeAll { $0 == n }
        case .invitation(let from, let answer): invite = Invite(from: from, answer: answer)
        case .connected(let n): state.connected(n); invite = nil
        case .disconnected: state.lost(); if link != nil { state.startSearch() }
        case .message(let msg): receive(msg)
        }
    }

    private func receive(_ msg: PeerMessage) {
        guard state.accept(msg), let src = Lang(rawValue: msg.lang), let model else { return }
        let mine = model.pair.mine
        let line = Line(mine: false, lang: src, text: msg.text)
        lines.append(line)
        guard src != mine else { return }
        let id = line.id
        Task {
            let tr = await model.translateText(msg.text, from: src, to: mine)
            guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
            lines[i].translation = tr
            if let tr, model.autoSpeak { model.announce(tr, lang: mine) }
        }
    }
}

struct TwoDeviceView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var session = PairSession()
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        Text(T("r34_pair_intro")).font(.footnote).foregroundStyle(.secondary)
                    }
                    switch session.state.phase {
                    case .idle:
                        Section {
                            Button { session.start() } label: { Label(T("r34_pair_search"), systemImage: "antenna.radiowaves.left.and.right") }
                        }
                    case .searching:
                        Section {
                            HStack { ProgressView(); Text(T("r34_pair_searching")) }
                            Text(String(format: T("r34_pair_me"), session.myName)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Section(T("r34_pair_nearby")) {
                            if session.nearby.isEmpty { Text(T("r34_pair_none")).foregroundStyle(.secondary) }
                            ForEach(session.nearby, id: \.self) { n in
                                Button { session.connect(n) } label: { Label(n, systemImage: "iphone.radiowaves.left.and.right") }
                            }
                        }
                    case .connected(let peer):
                        Section { Label(String(format: T("r34_pair_connected"), peer), systemImage: "checkmark.circle.fill").foregroundStyle(StatusColor.ok) }
                        Section {
                            ForEach(session.lines) { line in bubble(line) }
                        }
                    }
                    if session.running {
                        Section { Button(T("r34_pair_stop"), role: .destructive) { session.stop() } }
                    }
                }
                if case .connected = session.state.phase { composer }
            }
            .navigationTitle(T("r34_pair_title"))
            .navigationBarTitleDisplayMode(.inline)
            .doneToolbar { session.stop(); dismiss() }
            .onAppear { session.model = m }
            .onDisappear { session.stop() }
            .alert(T("r34_pair_invite_title"), isPresented: Binding(get: { session.invite != nil }, set: { if !$0 { session.invite?.answer(false); session.invite = nil } })) {
                Button(T("r34_pair_accept")) { session.invite?.answer(true); session.invite = nil }
                Button(T("r34_pair_decline"), role: .cancel) { session.invite?.answer(false); session.invite = nil }
            } message: { Text(String(format: T("r34_pair_invite_msg"), session.invite?.from ?? "")) }
        }
    }

    private func bubble(_ line: PairSession.Line) -> some View {
        VStack(alignment: line.mine ? .trailing : .leading, spacing: 2) {
            Text(line.text).font(.body)
            if let tr = line.translation { Text(tr).font(.title3.bold()).foregroundStyle(LangStyle.color(line.lang == m.pair.mine ? m.pair.partner : m.pair.mine, m.pair)) }
        }
        .frame(maxWidth: .infinity, alignment: line.mine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(A11yLabel.spoken(line.translation ?? line.text, line.translation == nil ? line.lang : m.pair.mine))
    }

    private var composer: some View {
        HStack {
            TextField(T("r34_pair_type"), text: $draft).textFieldStyle(.roundedBorder).focused($typing).submitLabel(.send)
                .onSubmit(send)
            Button(action: send) { Image(systemName: "paperplane.fill").minTapTarget() }
                .accessibilityLabel(T("r34_pair_send"))
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private func send() {
        session.send(draft, lang: m.pair.mine)
        draft = ""
    }
}
