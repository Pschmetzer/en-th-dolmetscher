// Views.swift – Hauptansicht: Kopf mit Sprachen und Status, Sprechblasen-Verlauf, Start-Knopf und Texteingabe.
import StoreKit
import SwiftUI

enum LangStyle {
    /// Meine Sprache blau, Partnersprache orange (wie bisher Englisch/Thai).
    static func color(_ l: Lang, _ pair: LangPair) -> Color { l == pair.partner ? .orange : .blue }
    static func flag(_ l: Lang) -> String { l.flag }
    static func name(_ l: Lang) -> String { l.native }
}

struct ContentView: View {
    @Environment(InterpreterModel.self) private var m
    @State private var showPartner = false
    @State private var big: Entry?
    @State private var editing: Entry?
    @State private var draft = ""
    @State private var confirmClear = false
    @FocusState private var typing: Bool

    var body: some View {
        @Bindable var m = m
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                history
                bottomBar
            }
            .navigationTitle("Dolmetscher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showPartner = true } label: { Image(systemName: "person.2.wave.2") }
                        .accessibilityLabel(T("partner"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { m.sheet = .phrasebook } label: { Label(T("phrasebook"), systemImage: "book") }
                        Button { m.sheet = .photo } label: { Label(T("photo_text"), systemImage: "text.viewfinder") }
                        Button { m.sheet = .emergency } label: { Label(T("emergency"), systemImage: "cross.case") }
                        if m.features.thaiExtras {
                            Button { m.sheet = .baht } label: { Label(T("baht_calc"), systemImage: "bahtsign.circle") }
                        }
                        if m.features.voiceCommands {
                            Button { m.sheet = .help } label: { Label(T("commands"), systemImage: "text.bubble") }
                        }
                        ShareLink(item: m.transcript) { Label(T("share"), systemImage: "square.and.arrow.up") }
                            .disabled(m.visibleEntries.isEmpty)
                        Button(role: .destructive) { confirmClear = true } label: { Label(T("clear"), systemImage: "trash") }
                            .disabled(m.visibleEntries.isEmpty)
                        Divider()
                        Button { m.sheet = .settings } label: { Label(T("settings"), systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel(T("more"))
                }
            }
            .sheet(item: $m.sheet) { s in sheetView(s) }
            .confirmationDialog(T("clear_confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(T("clear"), role: .destructive) { m.clear() }
                Button(T("cancel"), role: .cancel) {}
            }
            .alert(T("cellular_title"), isPresented: $m.cellularDownloadPrompt) {
                Button(T("cellular_go")) { m.startAllowingCellular() }
                Button(T("cellular_wait"), role: .cancel) {}
            } message: { Text(T("cellular_msg")) }
            .fullScreenCover(isPresented: $showPartner) { PartnerView() }
            .modifier(ReviewPrompt(covered: showPartner || big != nil))
            #if DEBUG
            .task { DebugScreens.apply(m, partner: $showPartner) }
            #endif
            .fullScreenCover(item: $big) { e in BigTextView(entryID: e.id) }
            .alert(T("edit_text"), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                EditAlert(entry: editing) { text in if let e = editing { m.edit(e.id, text: text) } }
            }
        }
    }

    @ViewBuilder private func sheetView(_ s: AppSheet) -> some View {
        switch s {
        case .settings: SettingsView()
        case .phrasebook: PhrasebookView()
        case .photo: PhotoTextView()
        case .emergency: EmergencyView()
        case .baht: BahtCalculatorView()
        case .allergy: AllergyCardView()
        case .privacy:
            NavigationStack {
                PrivacyView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { m.sheet = nil } } }
            }
        case .help:
            NavigationStack {
                ScrollView { CommandsCard().padding() }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { m.sheet = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Kopf

    private var header: some View {
        @Bindable var m = m
        return VStack(spacing: 10) {
            let p = m.pair
            HStack(spacing: 12) {
                Text("\(p.mine.flag) \(p.mine.native)").foregroundStyle(LangStyle.color(p.mine, p))
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                Text("\(p.partner.flag) \(p.partner.native)").foregroundStyle(LangStyle.color(p.partner, p))
            }
            .font(.title2.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityElement(children: .combine)
            Picker(T("direction"), selection: $m.mode) {
                if p.distinguishable { Text(T("mode_auto")).tag(Direction.auto) }
                Text("\(p.mine.flag) → \(p.partner.flag)").tag(Direction.mine)
                Text("\(p.partner.flag) → \(p.mine.flag)").tag(Direction.partner)
            }
            .pickerStyle(.segmented)
            .disabled(m.isBusy)
            if !p.distinguishable {
                // Gleiche Schrift (z. B. en/de): die Sprache lässt sich nicht sicher erkennen.
                Text(T("same_script_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            statusLine
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var statusText: String {
        if let n = m.notice { return n }
        switch m.phase {
        case .idle: return T("idle")
        case .loading:
            if m.whisperPreparing { return T("whisper_preparing") }
            guard let d = m.download else { return T("loading") }
            return "\(T("downloading")) \(LangStyle.flag(d.lang)) \(Int(d.fraction * 100)) %"
        case .failed(let e): return "⚠️ " + e
        case .listening:
            if m.interrupted { return "📞 " + T("interrupted") }
            if m.paused { return "⏸ " + T(m.features.voiceCommands ? "paused" : "paused_plain") }
            if m.speakingID != nil { return "🔊 " + T("speaking") }
            return m.hearing ? "🎙 " + T("hearing") : T("listening")
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if m.isBusy { ProgressView().controlSize(.small) }
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if m.canUndoClear {
                Button(T("undo")) { m.undoClear() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if m.micDenied, case .failed = m.phase, let url = URL(string: UIApplication.openSettingsURLString) {
                Button(T("open_settings")) { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .animation(.default, value: statusText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Verlauf

    private var history: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if m.hiddenCount > 0 {
                        Button { m.unlockHistory() } label: {
                            Label(String(format: T("lock_hidden"), m.hiddenCount), systemImage: "lock.fill")
                                .font(.footnote)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if m.visibleEntries.isEmpty && m.partial.isEmpty && m.hiddenCount == 0 {
                        EmptyState { m.submit(T("example_sentence")) }
                    }
                    ForEach(m.visibleEntries) { e in
                        Bubble(entry: e, onBig: { big = e }, onEdit: { editing = e }).id(e.id)
                    }
                    if !m.partial.isEmpty {
                        Text(m.partial)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .id("partial")
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: m.entries.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: m.entries.last?.translation) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: m.partial) { proxy.scrollTo("end", anchor: .bottom) }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    // MARK: Fuß

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Button { m.sheet = .phrasebook } label: { Image(systemName: "book").font(.title3) }
                    .accessibilityLabel(T("phrasebook"))
                Button { m.sheet = .photo } label: { Image(systemName: "text.viewfinder").font(.title3) }
                    .accessibilityLabel(T("photo_text"))
                TextField(T("type_hint"), text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                if !draft.isEmpty {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .accessibilityLabel(T("translate"))
                }
            }
            .padding(.horizontal)
            HStack(spacing: 16) {
                Button {
                    m.run(m.paused ? .resume : .pause)
                } label: {
                    Image(systemName: m.paused ? "play.fill" : "pause.fill")
                        .frame(width: 52, height: 52)
                        .background(.quaternary, in: Circle())
                }
                .disabled(!m.isListening)
                .accessibilityLabel(m.paused ? T("resume") : T("pause"))

                MicButton { typing = false }

                Button {
                    m.speakingID != nil ? m.stopSpeaking() : m.run(.repeat)
                } label: {
                    Image(systemName: m.speakingID != nil ? "speaker.slash.fill" : "arrow.counterclockwise")
                        .frame(width: 52, height: 52)
                        .background(.quaternary, in: Circle())
                }
                .disabled(m.entries.isEmpty)
                .accessibilityLabel(m.speakingID != nil ? T("stop_speaking") : T("cmd_repeat"))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    private func send() {
        m.submit(draft)
        draft = ""
    }
}

/// Bewertungsbitte nur, wenn nichts läuft und nichts offen ist (nie mitten im Gespräch).
struct ReviewPrompt: ViewModifier {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.requestReview) private var requestReview
    let covered: Bool

    private var ready: Bool { m.canAskReview && !covered }

    func body(content: Content) -> some View {
        content.onChange(of: ready) { _, ok in
            guard ok else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard ready else { return }
                m.reviewAsked()
                requestReview()
            }
        }
    }
}

/// Start/Stopp mit Pegel-Rand. Eigene View, damit der häufig wechselnde Pegel nur sie neu zeichnet.
struct MicButton: View {
    @Environment(InterpreterModel.self) private var m
    var before: () -> Void = {}

    var body: some View {
        let active = m.isListening || m.isBusy
        Button { before(); m.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: active ? "stop.fill" : "mic.fill")
                Text(active ? T("stop") : T("start"))
            }
            .font(.title3.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(active ? Color.red : Color.green, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: m.isListening ? CGFloat(m.level) * 6 : 0))
        }
        .accessibilityLabel(active ? T("stop") : T("start"))
    }
}

private struct EditAlert: View {
    let entry: Entry?
    var onSave: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField("", text: $text)
            .onAppear { text = entry?.text ?? "" }
        Button(T("translate")) { onSave(text) }
        Button(T("cancel"), role: .cancel) {}
    }
}

struct ProviderBadge: View {
    let provider: String?
    var body: some View {
        switch provider {
        case "apple": Image(systemName: "iphone").accessibilityLabel(T("prov_offline"))
        case "phrasebook": Image(systemName: "book.closed").accessibilityLabel(T("phrasebook"))
        case "google", "mymemory": Image(systemName: "globe").accessibilityLabel(T("prov_online"))
        case "card": Image(systemName: "hand.tap").accessibilityLabel(T("answer_cards"))
        default: EmptyView()
        }
    }
}

struct Bubble: View {
    @Environment(InterpreterModel.self) private var m

    private func backColor(_ off: Bool) -> Color { off ? Color.orange : Color.secondary }
    private func backA11yLabel(_ off: Bool, _ b: String) -> String {
        let warn: String = off ? T("back_deviates") + ". " : ""
        let label: String = T("back_label")
        return warn + label + ": " + b
    }
    let entry: Entry
    var onBig: () -> Void
    var onEdit: () -> Void

    var body: some View {
        let color: Color = LangStyle.color(entry.target, m.pair)
        let fromPartner: Bool = entry.src == m.pair.partner
        HStack {
            if fromPartner { Spacer(minLength: 36) }
            accessible(card(color))
            if !fromPartner { Spacer(minLength: 36) }
        }
    }

    // Aufgeteilt in kleine Teile mit festen Typen – sonst braucht der Compiler zu lange (CI-Fehler).

    @ViewBuilder private func translationPart(_ color: Color) -> some View {
        if let t = entry.translation {
            Text(t)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
            RomanLine(text: roman)
            if m.backCheck, let b = entry.back { BackLine(text: b, deviates: entry.backDeviates) }
        } else if let err = entry.error {
            HStack {
                Text("⚠️ " + err).font(.callout).foregroundStyle(.red)
                Button(T("retry")) { m.retry(entry.id) }.buttonStyle(.bordered).controlSize(.small)
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(T("translating")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func card(_ color: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        let ring: Double = m.speakingID == entry.id ? 0.8 : 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(LangStyle.flag(entry.src)) \(entry.text)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            translationPart(color)
            actions
        }
        .padding(12)
        .background(color.opacity(0.12), in: shape)
        .overlay(shape.stroke(color.opacity(ring), lineWidth: 2))
        .contentShape(shape)
        .onTapGesture { if entry.translation != nil { onBig() } }
        .contextMenu { menu }
    }

    /// VoiceOver: eine Blase = ein Element; die Knöpfe als Aktionen.
    private func accessible<V: View>(_ v: V) -> some View {
        let done: Bool = entry.translation != nil
        let traits: AccessibilityTraits = done ? .isButton : []
        let hint: String = done ? T("show_big") : ""
        return v
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel)
            .accessibilityAddTraits(traits)
            .accessibilityHint(hint)
            .accessibilityAction { if done { onBig() } }
            .accessibilityActions { a11yActions }
    }

    private var roman: String? { m.showRoman ? entry.romanized : entry.roman }

    private var a11yLabel: String {
        var parts = ["\(entry.src.name(in: L10n.lang)): \(entry.text)"]
        if let t = entry.translation {
            parts.append("\(entry.target.name(in: L10n.lang)): \(t)")
            if m.backCheck, entry.backDeviates { parts.append(T("back_deviates")) }
        }
        else if let err = entry.error { parts.append(err) }
        else { parts.append(T("translating")) }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder private var a11yActions: some View {
        if entry.translation != nil {
            Button(T("replay")) { m.speak(entry) }
            Button(T("replay_slow")) { m.speak(entry, slow: true) }
            Button(m.isFavorite(entry) ? T("unfavorite") : T("favorite")) { m.toggleFavorite(entry) }
        }
        if entry.error != nil { Button(T("retry")) { m.retry(entry.id) } }
        if entry.alt?.isEmpty == false { Button(T("swap")) { m.swapLanguage(entry.id) } }
        Button(T("edit_text"), action: onEdit)
        Button(T("delete")) { m.delete(entry.id) }
    }

    private var actions: some View {
        HStack(spacing: 18) {
            if entry.translation != nil {
                Button {
                    m.speakingID == entry.id ? m.stopSpeaking() : m.speak(entry)
                } label: {
                    Image(systemName: m.speakingID == entry.id ? "stop.circle.fill" : "speaker.wave.2.fill")
                }
                .accessibilityLabel(m.speakingID == entry.id ? T("stop_speaking") : T("replay"))
                Button { m.speak(entry, slow: true) } label: { Image(systemName: "tortoise") }
                    .accessibilityLabel(T("replay_slow"))
                Button { m.toggleFavorite(entry) } label: {
                    Image(systemName: m.isFavorite(entry) ? "star.fill" : "star")
                        .foregroundStyle(m.isFavorite(entry) ? Color.yellow : Color.secondary)
                }
                .accessibilityLabel(m.isFavorite(entry) ? T("unfavorite") : T("favorite"))
            }
            if let alt = entry.alt, !alt.isEmpty {
                Button { m.swapLanguage(entry.id) } label: {
                    Label(LangStyle.flag(entry.target), systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel(T("swap"))
            }
            Spacer(minLength: 0)
            ProviderBadge(provider: entry.provider).font(.caption)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    @ViewBuilder private var menu: some View {
        if let t = entry.translation {
            Button { UIPasteboard.general.string = t } label: { Label(T("copy"), systemImage: "doc.on.doc") }
            ShareLink(item: "\(entry.text)\n\(t)") { Label(T("share_one"), systemImage: "square.and.arrow.up") }
            Button(action: onBig) { Label(T("show_big"), systemImage: "arrow.up.left.and.arrow.down.right") }
        }
        Button(action: onEdit) { Label(T("edit_text"), systemImage: "pencil") }
        if entry.alt?.isEmpty == false {
            Button { m.swapLanguage(entry.id) } label: { Label(T("swap"), systemImage: "arrow.triangle.2.circlepath") }
        }
        Button(role: .destructive) { m.delete(entry.id) } label: { Label(T("delete"), systemImage: "trash") }
    }
}

/// Eine Übersetzung bildschirmfüllend – zum Zeigen (Taxifahrer, Kellner).
struct BigTextView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var flipped = false

    var body: some View {
        let e = m.entries.first { $0.id == entryID }
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(e?.translation ?? "")
                    .font(.system(size: 72, weight: .bold))
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LangStyle.color(e?.target ?? m.pair.partner, m.pair))
                RomanLine(text: m.showRoman ? e?.romanized : e?.roman, font: .title3)
                Text(e?.text ?? "").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotationEffect(.degrees(flipped ? 180 : 0))
            .onTapGesture { dismiss() }
            Divider()
            HStack(spacing: 28) {
                Button { flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel(T("flip"))
                Button { if let e { m.speak(e) } } label: { Image(systemName: "speaker.wave.2.fill") }
                    .accessibilityLabel(T("replay"))
                Button { if let e { m.speak(e, slow: true) } } label: { Image(systemName: "tortoise.fill") }
                    .accessibilityLabel(T("replay_slow"))
                Spacer()
                Button(T("done")) { dismiss() }
            }
            .font(.title2)
            .padding()
        }
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = m.isListening }
    }
}

struct EmptyState: View {
    @Environment(InterpreterModel.self) private var m
    var tryExample: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(String(format: T("empty_hint_pair"), m.pair.mine.name(in: L10n.lang), m.pair.partner.name(in: L10n.lang)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // Beispielsatz nur, wenn die Sprache der Oberfläche im Paar ist (sonst würde er falsch erkannt).
            if let ui = L10n.asLang, m.pair.contains(ui) {
            Button(action: tryExample) {
                Text(String(format: T("empty_example_fmt"), T("example_sentence")))
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Button { m.sheet = .phrasebook } label: { Label(T("phrasebook"), systemImage: "book") }
                Button { m.sheet = .photo } label: { Label(T("photo_text"), systemImage: "text.viewfinder") }
                Button { m.sheet = .emergency } label: { Label(T("emergency"), systemImage: "cross.case") }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
            .font(.footnote)
            if !m.offlineReady {
                Button { m.sheet = .settings } label: {
                    Label(T(m.allowOnline ? "online_hint" : "offline_hint"), systemImage: m.allowOnline ? "globe" : "arrow.down.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
            if m.features.voiceCommands { CommandsCard() }
        }
        .padding(.top, 8)
    }
}

struct CommandsCard: View {
    private let rows: [(String, String)] = [
        ("pause", "cmd_pause"), ("resume", "cmd_resume"), ("repeat", "cmd_repeat"),
        ("slower · faster", "cmd_slower"), ("louder · quieter", "cmd_louder"), ("clear", "cmd_clear"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(T("commands"), systemImage: "text.bubble").font(.headline)
            Text(T("commands_say")).font(.subheadline).foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text("“Translator, \(row.0)”").font(.callout.weight(.semibold))
                    Text(T(row.1)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Umschrift unter einer Übersetzung (eigene View: hält den Ausdruck in `Bubble` für den Compiler klein).
struct RomanLine: View {
    let text: String?
    var font: Font = .caption
    var body: some View {
        if let text { Text(text).font(font).italic().foregroundStyle(.secondary) }
    }
}

/// Rückübersetzung, bei Abweichung orange mit Warnzeichen.
struct BackLine: View {
    let text: String
    let deviates: Bool

    private var icon: String { deviates ? "exclamationmark.triangle.fill" : "arrow.uturn.backward" }
    private var tint: Color { deviates ? .orange : .secondary }
    private var label: String {
        let head: String = T("back_label") + ": " + text
        return deviates ? T("back_deviates") + ". " + head : head
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
