// Views.swift – Hauptansicht: Kopf mit Sprachen und Status, Sprechblasen-Verlauf, Start-Knopf und Texteingabe.
import SwiftUI

enum LangStyle {
    static func color(_ l: Lang) -> Color { l == .th ? .orange : .blue }
    static func flag(_ l: Lang) -> String { l == .th ? "🇹🇭" : "🇬🇧" }
    static func name(_ l: Lang) -> String { l == .th ? "ไทย" : "English" }
}

struct ContentView: View {
    @Environment(InterpreterModel.self) private var m
    @State private var showSettings = false
    @State private var showPartner = false
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
                        Button { m.showHelp = true } label: { Label(T("commands"), systemImage: "text.bubble") }
                        ShareLink(item: m.transcript) { Label(T("share"), systemImage: "square.and.arrow.up") }
                            .disabled(m.entries.isEmpty)
                        Button(role: .destructive) { m.clear() } label: { Label(T("clear"), systemImage: "trash") }
                            .disabled(m.entries.isEmpty)
                        Divider()
                        Button { showSettings = true } label: { Label(T("settings"), systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $m.showHelp) {
                NavigationStack {
                    ScrollView { CommandsCard().padding() }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { m.showHelp = false } } }
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showPartner) { PartnerView() }
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
            Picker("", selection: $m.mode) {
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
            guard let d = m.download else { return T("loading") }
            return "\(T("downloading")) \(LangStyle.flag(d.lang)) \(Int(d.fraction * 100)) %"
        case .failed(let e): return "⚠️ " + e
        case .listening:
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
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .animation(.default, value: statusText)
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
                        Bubble(entry: e).id(e.id)
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
            .onChange(of: m.entries) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: m.partial) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    // MARK: Fuß

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                TextField(T("type_hint"), text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                if !draft.isEmpty {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
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

                Button { typing = false; m.toggle() } label: {
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

                Button {
                    m.speakingID != nil ? m.stopSpeaking() : m.run(.repeat)
                } label: {
                    Image(systemName: m.speakingID != nil ? "speaker.slash.fill" : "arrow.counterclockwise")
                        .frame(width: 52, height: 52)
                        .background(.quaternary, in: Circle())
                }
                .disabled(m.entries.isEmpty)
                .accessibilityLabel(T("cmd_repeat"))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    private var active: Bool { m.isListening || m.isBusy }

    private func send() {
        m.submit(draft)
        draft = ""
    }
}

struct Bubble: View {
    @Environment(InterpreterModel.self) private var m
    let entry: Entry

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
                        .textSelection(.enabled)
                } else if let err = entry.error {
                    HStack {
                        Text("⚠️ " + err).font(.callout).foregroundStyle(.red)
                        Button(T("retry")) { m.retry(entry.id) }.buttonStyle(.bordered).controlSize(.small)
                    }
                } else {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text(T("translating")).font(.callout).foregroundStyle(.secondary) }
                }
                HStack(spacing: 18) {
                    if entry.translation != nil {
                        Button {
                            m.speakingID == entry.id ? m.stopSpeaking() : m.speak(entry)
                        } label: {
                            Image(systemName: m.speakingID == entry.id ? "stop.circle.fill" : "speaker.wave.2.fill")
                        }
                        .accessibilityLabel(T("replay"))
                    }
                    if let alt = entry.alt, !alt.isEmpty {
                        Button { m.swapLanguage(entry.id) } label: {
                            Label(LangStyle.flag(entry.src.other), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityLabel(T("swap"))
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(m.speakingID == entry.id ? 0.8 : 0), lineWidth: 2))
            .contextMenu {
                if let t = entry.translation {
                    Button { UIPasteboard.general.string = t } label: { Label(T("copy"), systemImage: "doc.on.doc") }
                }
                if entry.alt?.isEmpty == false {
                    Button { m.swapLanguage(entry.id) } label: { Label(T("swap"), systemImage: "arrow.triangle.2.circlepath") }
                }
            }
            if entry.src == .en { Spacer(minLength: 36) }
        }
    }
}

struct EmptyState: View {
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

/// Große Anzeige der letzten Übersetzung für das Gegenüber – auf Wunsch um 180° gedreht (Handy liegt zwischen beiden).
struct PartnerView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @AppStorage("partnerFlipped") private var flipped = false

    var body: some View {
        let last = m.entries.last { $0.translation != nil }
        VStack(spacing: 0) {
            Group {
                if let e = last, let t = e.translation {
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
            .rotationEffect(.degrees(flipped ? 180 : 0))
            Divider()
            HStack {
                Button { flipped.toggle() } label: { Label(T("flip"), systemImage: "arrow.up.arrow.down") }
                Spacer()
                Button { m.toggle() } label: {
                    Image(systemName: m.isListening || m.isBusy ? "stop.fill" : "mic.fill")
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(m.isListening || m.isBusy ? Color.red : Color.green, in: Circle())
                }
                Spacer()
                Button(T("done")) { dismiss() }
            }
            .padding()
        }
    }
}
