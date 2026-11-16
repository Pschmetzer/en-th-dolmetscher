// ConversationView.swift – Ansicht für das Gegenüber: groß (eine Person liest) oder geteilt (Konversationsmodus:
// Handy liegt zwischen beiden, obere Hälfte für das Gegenüber um 180° gedreht). Jede Hälfte zeigt das Gespräch in
// ihrer Sprache, live mitgeschrieben, mit eigenem „Jetzt Sie/ich“-Knopf; das Gegenüber kann Antwortkarten antippen.
import SwiftUI

struct PartnerView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @AppStorage("partnerFlipped") private var flipped = false
    @AppStorage("partnerSplit") private var split = true

    var body: some View {
        VStack(spacing: 0) {
            if split {
                ConversationSide(lang: m.pair.partner, isPartner: true)
                    .rotationEffect(.degrees(180))
                Divider()
                controls
                Divider()
                ConversationSide(lang: m.pair.mine, isPartner: false)
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

    private var single: some View {
        Group {
            if let e = m.visibleEntries.last(where: { $0.translation != nil }), let t = e.translation {
                VStack(spacing: 12) {
                    Text(t)
                        .font(.system(size: 64, weight: .bold))
                        .minimumScaleFactor(0.25)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LangStyle.color(e.target, m.pair))
                    if m.showRoman, let r = e.romanized { Text(r).font(.title3).italic().foregroundStyle(.secondary) }
                }
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

/// Eine Hälfte des Konversationsmodus: alles in `lang`.
struct ConversationSide: View {
    @Environment(InterpreterModel.self) private var m
    let lang: Lang
    let isPartner: Bool
    @State private var digits: String?

    /// Satz in der Sprache dieser Seite: was hier gesagt wurde (Original) oder was für hier übersetzt wurde.
    private func line(_ e: Entry) -> (text: String, own: Bool)? {
        if e.src == lang { return (e.text, true) }
        if e.target == lang, let t = e.translation { return (t, false) }
        return nil
    }

    private var expecting: Bool { m.expected == lang }

    var body: some View {
        let color = LangStyle.color(lang, m.pair)
        VStack(spacing: 10) {
            if let d = digits {
                NumberPad(digits: d, lang: lang,
                          onChange: { digits = $0 },
                          onDone: { m.answerNumber(d); digits = nil },
                          onCancel: { digits = nil })
            } else {
                messages(color)
                if isPartner { answerCards }
            }
            turnButton(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.opacity(expecting ? 0.14 : 0.05))
        .overlay(Rectangle().stroke(color.opacity(expecting ? 0.8 : 0), lineWidth: 3))
        .animation(.default, value: expecting)
    }

    private struct Line: Identifiable {
        let entry: Entry
        let text: String
        let own: Bool
        var id: UUID { entry.id }
    }

    private func messages(_ color: Color) -> some View {
        let shown = Array(m.visibleEntries.compactMap { e in line(e).map { Line(entry: e, text: $0.text, own: $0.own) } }.suffix(6))
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    if shown.isEmpty && m.partial.isEmpty {
                        Text(L10n.text("just_talk", lang: L10n.uiCode(lang)) ?? "\(lang.flag) 🎙")
                            .font(.title.bold())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(shown) { l in
                        Button { m.speak(l.entry) } label: {
                            VStack(alignment: l.own ? .trailing : .leading, spacing: 2) {
                                Text(l.text)
                                    .font(l.own ? .body : .title2.weight(.bold))
                                    .foregroundStyle(l.own ? Color.secondary : color)
                                    .multilineTextAlignment(l.own ? .trailing : .leading)
                                if !l.own, m.showRoman, let r = Romanizer.latin(l.text, lang) {
                                    Text(r).font(.caption).italic().foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: l.own ? .trailing : .leading)
                        }
                        .buttonStyle(.plain)
                        .id(l.id)
                        .accessibilityHint(T("replay"))
                    }
                    // Live-Untertitel: was gerade gesprochen wird (auch für Hörgeschädigte)
                    if !m.partial.isEmpty || (m.hearing && m.isListening) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PartnerPhrases.text(.listening, lang)).font(.caption).foregroundStyle(.secondary)
                            if !m.partial.isEmpty { Text(m.partial).font(.title3).foregroundStyle(.primary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("live")
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: shown.last?.id) { withAnimation { proxy.scrollTo(shown.last?.id, anchor: .bottom) } }
            .onChange(of: m.partial) { proxy.scrollTo("live", anchor: .bottom) }
            .onAppear { proxy.scrollTo(shown.last?.id, anchor: .bottom) }
        }
    }

    private var answerCards: some View {
        HStack(spacing: 8) {
            card(PartnerPhrases.text(.yes, lang), .green) { m.answer(.yes) }
            card(PartnerPhrases.text(.no, lang), .red) { m.answer(.no) }
            card(PartnerPhrases.text(.dontKnow, lang), .gray) { m.answer(.dontKnow) }
            card("123", .blue) { digits = "" }
                .accessibilityLabel(PartnerPhrases.text(.number, lang))
        }
    }

    private func card(_ title: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private func turnButton(_ color: Color) -> some View {
        Button { m.expectSpeaker(lang) } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                Text(isPartner ? PartnerPhrases.text(.nowYou, lang) : T("now_me"))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .font(.title3.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(color.opacity(expecting ? 1 : 0.75), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(expecting ? .isSelected : [])
    }
}

/// Zahlenfeld der Antwortkarte „Zahl“ (Preis, Uhrzeit, Anzahl) – in der gedrehten Hälfte des Gegenübers.
struct NumberPad: View {
    let digits: String
    let lang: Lang
    var onChange: (String) -> Void
    var onDone: () -> Void
    var onCancel: () -> Void

    private let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["000", "0", "✓"]]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: onCancel) { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text(digits.isEmpty ? PartnerPhrases.text(.number, lang) : NumberCard.spoken(digits, in: lang))
                    .font(.title.bold().monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .foregroundStyle(digits.isEmpty ? .secondary : .primary)
                Spacer()
                Button { onChange(String(digits.dropLast())) } label: { Image(systemName: "delete.left").font(.title2) }
                    .buttonStyle(.plain).disabled(digits.isEmpty)
            }
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { k in
                        Button { press(k) } label: {
                            Text(k).font(.title2.bold().monospacedDigit()).frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .tint(k == "✓" ? .green : .primary)
                        .disabled(k == "✓" && digits.isEmpty)
                    }
                }
            }
        }
    }

    private func press(_ k: String) {
        if k == "✓" { onDone(); return }
        var d = digits
        for c in k { d = NumberCard.append(c, to: d) }
        onChange(d)
    }
}
