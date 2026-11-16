// Views.swift – Hauptansicht: Kopf mit Sprachen und Status, Sprechblasen-Verlauf, Start-Knopf und Texteingabe.
import SwiftUI

enum LangStyle {
    static func color(_ l: Lang) -> Color { l == .th ? .orange : .blue }
    static func flag(_ l: Lang) -> String { l == .th ? "🇹🇭" : "🇬🇧" }
    static func name(_ l: Lang) -> String { l == .th ? "ไทย" : "English" }
}

struct ContentView: View {
    @Environment(InterpreterModel.self) private var m
    @State private var showPartner = false
    @State private var big: Entry?
    @State private var editing: Entry?
    @State private var draft = ""
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
                        Button { m.sheet = .baht } label: { Label(T("baht_calc"), systemImage: "bahtsign.circle") }
                        Button { m.sheet = .help } label: { Label(T("commands"), systemImage: "text.bubble") }
                        ShareLink(item: m.transcript) { Label(T("share"), systemImage: "square.and.arrow.up") }
                            .disabled(m.entries.isEmpty)
                        Button(role: .destructive) { m.clear() } label: { Label(T("clear"), systemImage: "trash") }
                            .disabled(m.entries.isEmpty)
                        Divider()
                        Button { m.sheet = .settings } label: { Label(T("settings"), systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel(T("more"))
                }
            }
            .sheet(item: $m.sheet) { s in
                switch s {
                case .settings: SettingsView()
                case .phrasebook: PhrasebookView()
                case .photo: PhotoTextView()
                case .emergency: EmergencyView()
                case .baht: BahtCalculatorView()
                case .help:
                    NavigationStack {
                        ScrollView { CommandsCard().padding() }
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { m.sheet = nil } } }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .fullScreenCover(isPresented: $showPartner) { PartnerView() }
            .fullScreenCover(item: $big) { e in BigTextView(entryID: e.id) }
            .alert(T("edit_text"), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                EditAlert(entry: editing) { text in if let e = editing { m.edit(e.id, text: text) } }
            }
        }
    }

    // MARK: Kopf

    private var header: some View {
        @Bindable var m = m
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("\(LangStyle.flag(.en)) English").foregroundStyle(LangStyle.color(.en))
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                Text("\(LangStyle.flag(.th)) ไทย").foregroundStyle(LangStyle.color(.th))
            }
            .font(.title2.bold())
            .accessibilityElement(children: .combine)
            Picker(T("direction"), selection: $m.mode) {
                Text(T("mode_auto")).tag(InterpreterModel.Mode.auto)
                Text("\(LangStyle.flag(.en)) → \(LangStyle.flag(.th))").tag(InterpreterModel.Mode.en)
                Text("\(LangStyle.flag(.th)) → \(LangStyle.flag(.en))").tag(InterpreterModel.Mode.th)
            }
            .pickerStyle(.segmented)
            .disabled(m.isBusy)
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
            if m.paused { return "⏸ " + T("paused") }
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
                    if m.entries.isEmpty && m.partial.isEmpty {
                        EmptyState { m.submit("Where is the toilet?") }
                    }
                    ForEach(m.entries) { e in
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
        default: EmptyView()
        }
    }
}

struct Bubble: View {
    @Environment(InterpreterModel.self) private var m
    let entry: Entry
    var onBig: () -> Void
    var onEdit: () -> Void

    var body: some View {
        let color = LangStyle.color(entry.src.other)
        HStack {
            if entry.src == .th { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 6) {
                Text("\(LangStyle.flag(entry.src)) \(entry.text)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let t = entry.translation {
                    Text(t)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color)
                    if let r = entry.roman { Text(r).font(.caption).italic().foregroundStyle(.secondary) }
                } else if let err = entry.error {
                    HStack {
                        Text("⚠️ " + err).font(.callout).foregroundStyle(.red)
                        Button(T("retry")) { m.retry(entry.id) }.buttonStyle(.bordered).controlSize(.small)
                    }
                } else {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text(T("translating")).font(.callout).foregroundStyle(.secondary) }
                }
                actions
            }
            .padding(12)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(m.speakingID == entry.id ? 0.8 : 0), lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { if entry.translation != nil { onBig() } }
            .accessibilityAction(named: T("show_big")) { if entry.translation != nil { onBig() } }
            .contextMenu { menu }
            if entry.src == .en { Spacer(minLength: 36) }
        }
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
                    Label(LangStyle.flag(entry.src.other), systemImage: "arrow.triangle.2.circlepath")
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
                    .foregroundStyle(LangStyle.color(e?.src.other ?? .th))
                if let r = e?.roman { Text(r).font(.title3).italic().foregroundStyle(.secondary) }
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
            Text(T("empty_hint"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: tryExample) {
                Text(T("empty_example"))
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                Button { m.sheet = .phrasebook } label: { Label(T("phrasebook"), systemImage: "book") }
                Button { m.sheet = .photo } label: { Label(T("photo_text"), systemImage: "text.viewfinder") }
                Button { m.sheet = .emergency } label: { Label(T("emergency"), systemImage: "cross.case") }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
            .font(.footnote)
            if !m.offlineReady && m.allowOnline {
                Button { m.sheet = .settings } label: {
                    Label(T("online_hint"), systemImage: "globe")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
            CommandsCard()
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

/// Für das Gegenüber: groß (eine Person liest) oder geteilt (Handy liegt zwischen beiden, obere Hälfte gedreht).
struct PartnerView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @AppStorage("partnerFlipped") private var flipped = false
    @AppStorage("partnerSplit") private var split = true

    /// Letzter Satz in der gewünschten Sprache (Original oder Übersetzung).
    private func latest(in lang: Lang) -> String? {
        guard let e = m.entries.last(where: { $0.translation != nil }) else { return nil }
        return e.src == lang ? e.text : e.translation
    }

    var body: some View {
        VStack(spacing: 0) {
            if split {
                side(.th).rotationEffect(.degrees(180))
                Divider()
                controls
                Divider()
                side(.en)
            } else {
                single.rotationEffect(.degrees(flipped ? 180 : 0))
                Divider()
                controls
            }
        }
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = m.isListening }
    }

    private func side(_ lang: Lang) -> some View {
        Text(latest(in: lang) ?? (lang == .th ? "พูดได้เลย" : "Just talk"))
            .font(.system(size: 48, weight: .bold))
            .minimumScaleFactor(0.2)
            .multilineTextAlignment(.center)
            .foregroundStyle(latest(in: lang) == nil ? Color.secondary : LangStyle.color(lang))
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LangStyle.color(lang).opacity(0.06))
    }

    private var single: some View {
        Group {
            if let e = m.entries.last(where: { $0.translation != nil }), let t = e.translation {
                Text(t)
                    .font(.system(size: 64, weight: .bold))
                    .minimumScaleFactor(0.25)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LangStyle.color(e.src.other))
            } else {
                Text(T("partner_empty")).font(.title2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack {
            Button { split.toggle() } label: {
                Image(systemName: split ? "rectangle" : "rectangle.split.1x2")
            }
            .accessibilityLabel(T("split_view"))
            if !split {
                Button { flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel(T("flip"))
            }
            Spacer()
            MicButton().frame(maxWidth: 200)
            Spacer()
            Button(T("done")) { dismiss() }
        }
        .font(.title3)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
