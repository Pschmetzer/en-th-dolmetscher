// ConversationView.swift – Ansicht für das Gegenüber: groß (eine Person liest) oder geteilt (Konversationsmodus:
// Handy liegt zwischen beiden, obere Hälfte für das Gegenüber um 180° gedreht). Jede Hälfte zeigt das Gespräch in
// ihrer Sprache, live mitgeschrieben, mit eigenem „Jetzt Sie/ich“-Knopf; das Gegenüber kann Antwortkarten antippen.
import SwiftUI

struct PartnerView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var scaled64: CGFloat = 64
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @AppStorage("partnerFlipped") private var flipped = false
    @AppStorage("partnerSplit") private var split = true

    var body: some View {
        GeometryReader { geo in
        VStack(spacing: 0) {
            if split && ConversationLogic.sideBySide(width: geo.size.width, height: geo.size.height) {
                // Querformat/iPad: nebeneinander, die Steuerung darunter.
                HStack(spacing: 0) {
                    ConversationSide(lang: m.pair.partner, isPartner: true)
                        .rotationEffect(.degrees(180))
                        .accessibilitySortPriority(1)
                    Divider()
                    ConversationSide(lang: m.pair.mine, isPartner: false)
                        .accessibilitySortPriority(2)
                }
                Divider()
                controls
            } else if split {
                ConversationSide(lang: m.pair.partner, isPartner: true)
                    .rotationEffect(.degrees(180))
                    .accessibilitySortPriority(1)   // gedreht: VoiceOver liest zuerst die eigene (untere) Hälfte
                Divider()
                controls
                Divider()
                ConversationSide(lang: m.pair.mine, isPartner: false)
                    .accessibilitySortPriority(2)
            } else {
                single.rotationEffect(.degrees(flipped ? 180 : 0))
                Divider()
                controls
            }
        }
        }
        .persistentSystemOverlays(.hidden)
        .modifier(FullBrightness())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }   // Bildschirm bleibt an
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = m.isListening }
    }

    private var single: some View {
        Group {
            if let e = m.visibleEntries.last(where: { $0.translation != nil }), let t = e.translation {
                VStack(spacing: 12) {
                    Text(t)
                        .font(.system(size: scaled64, weight: .bold))
                        .minimumScaleFactor(0.25)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LangStyle.color(e.target, m.pair))
                        .spokenIn(e.target.voiceLocale, t)
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
            Button { split.toggle(); Haptics.tap() } label: {
                Image(systemName: split ? "rectangle" : "rectangle.split.1x2").minTapTarget()
            }
            .accessibilityLabel(T("split_view"))
            if !split {
                Button { flipped.toggle(); Haptics.command() } label: { Image(systemName: "arrow.up.arrow.down").minTapTarget() }
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
    @Environment(\.accessibilityDifferentiateWithoutColor) private var noColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(InterpreterModel.self) private var m
    let lang: Lang
    let isPartner: Bool
    @State private var digits: String?
    @State private var reply = ""
    @AppStorage("convFontStepMine") private var fontMine = ConversationLogic.defaultFontStep
    @AppStorage("convFontStepPartner") private var fontPartner = ConversationLogic.defaultFontStep

    private var fontStep: Int { ConversationLogic.clampStep(isPartner ? fontPartner : fontMine) }
    private func bumpFont(_ d: Int) {
        let n = ConversationLogic.stepped(fontStep, by: d)
        if isPartner { fontPartner = n } else { fontMine = n }
        Haptics.tap()
    }

    private var sideState: ConversationLogic.SideState {
        ConversationLogic.state(expecting: expecting, listening: m.isListening, hearing: m.hearing,
                                translating: m.finishing && expecting, speaking: m.speakingID != nil)
    }

    /// Satz in der Sprache dieser Seite: was hier gesagt wurde (Original) oder was für hier übersetzt wurde.
    private func line(_ e: Entry) -> (text: String, own: Bool)? {
        if e.src == lang { return (e.text, true) }
        if e.target == lang, let t = e.translation { return (t, false) }
        return nil
    }

    private var expecting: Bool { m.expected == lang }

    var body: some View {
        let color = LangStyle.color(lang, m.pair)
        let fill = LangStyle.fill(lang, m.pair)
        VStack(spacing: 10) {
            if let d = digits {
                NumberPad(digits: d, lang: lang,
                          onChange: { digits = $0 },
                          onDone: { m.answerNumber(d); digits = nil },
                          onCancel: { digits = nil })
            } else {
                toolbar
                messages(color)
                if isPartner { answerCards; replyField }
            }
            turnButton(fill)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.opacity(expecting ? 0.14 : 0.05))
        .overlay(Rectangle().stroke(color.opacity(expecting ? 0.8 : 0), lineWidth: noColor && expecting ? 6 : 3))
        .overlay(alignment: .topLeading) {
            if noColor && expecting { Image(systemName: "mic.fill").padding(8).accessibilityHidden(true) }
        }
        .animation(Motion.animation(reduce: reduceMotion), value: expecting)
    }

    /// Zustand (Text + Symbol), Schriftgröße, Sprachwechsel, Wiederholen und Langsam dieser Hälfte.
    private var toolbar: some View {
        let st = sideState
        let last = ConversationLogic.lastSpeakable(m.visibleEntries, lang: lang)
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                Label(L10n.text(ConversationLogic.textKey(st), lang: L10n.uiCode(lang)) ?? T(ConversationLogic.textKey(st)),
                      systemImage: ConversationLogic.icon(st))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityLabel(T(ConversationLogic.textKey(st)))
                Spacer()
                Menu {
                    ForEach(Lang.all.filter { $0 != m.pair.other(lang) }, id: \.self) { l in
                        Button("\(l.flag) \(l.native)") { setLang(l) }
                    }
                } label: { Text("\(lang.flag) \(lang.native)").font(.footnote).minTapTarget() }
                    .accessibilityLabel(T("conv_language"))
            }
            HStack(spacing: 6) {
                Button { bumpFont(-1) } label: { Image(systemName: "textformat.size.smaller").minTapTarget() }
                    .disabled(fontStep == 0).accessibilityLabel(T("conv_font_smaller"))
                Button { bumpFont(1) } label: { Image(systemName: "textformat.size.larger").minTapTarget() }
                    .disabled(fontStep == ConversationLogic.fontScales.count - 1).accessibilityLabel(T("conv_font_larger"))
                Spacer()
                Button { if let e = last { m.speak(e) } } label: { Label(T("conv_repeat"), systemImage: "arrow.counterclockwise").labelStyle(.titleAndIcon) }
                    .disabled(last == nil)
                Button { if let e = last { m.speak(e, slow: true) } } label: { Label(T("conv_slow"), systemImage: "tortoise.fill").labelStyle(.titleAndIcon) }
                    .disabled(last == nil)
            }
            .font(.footnote)
            .buttonStyle(.bordered)
        }
    }

    private func setLang(_ l: Lang) {
        var p = m.pair
        if isPartner { p.partner = l } else { p.mine = l }
        m.pair = p
        Haptics.tap()
    }

    struct Line: Identifiable {
        let entry: Entry
        let text: String
        let own: Bool
        var id: UUID { entry.id }
    }

    private func messages(_ color: Color) -> some View {
        let shown = m.visibleEntries.compactMap { e in line(e).map { Line(entry: e, text: $0.text, own: $0.own) } }   // ganzer Verlauf, scrollbar
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
                    ForEach(shown) { (l: Line) in
                        LineRow(entry: l.entry, text: l.text, own: l.own, lang: lang, color: color, scale: ConversationLogic.scale(step: fontStep)).id(l.id)
                    }
                    // Live-Untertitel: was gerade gesprochen wird (auch für Hörgeschädigte)
                    if !m.partial.isEmpty || (m.hearing && m.isListening) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PartnerPhrases.text(.listening, lang)).font(.caption).foregroundStyle(.secondary)
                            if !m.partial.isEmpty { Text(m.partial).font(.title3).foregroundStyle(.primary).spokenIn(lang.voiceLocale, m.partial) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("live")
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: shown.last?.id) { withAnimation(Motion.animation(reduce: reduceMotion)) { proxy.scrollTo(shown.last?.id, anchor: .bottom) } }
            .onChange(of: m.partial) { proxy.scrollTo("live", anchor: .bottom) }
            .onAppear { proxy.scrollTo(shown.last?.id, anchor: .bottom) }
        }
    }

    /// Eigene Antwort tippen (Tastatur in der Partnersprache): wird in meine Sprache übersetzt und angezeigt.
    private var replyField: some View {
        HStack(spacing: 8) {
            TextField(lang.native, text: $reply, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit(sendReply)
            Button(action: sendReply) { Image(systemName: "arrow.up.circle.fill").font(.title).minTapTarget() }
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(T("translate"))
        }
    }

    private func sendReply() {
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        m.submit(t, speak: false, from: lang)
        reply = ""
    }

    private var answerCards: some View {
        HStack(spacing: 8) {
            card(PartnerPhrases.text(.yes, lang), StatusColor.ok, icon: "checkmark") { m.answer(.yes) }
            card(PartnerPhrases.text(.no, lang), StatusColor.error, icon: "xmark") { m.answer(.no) }
            card(PartnerPhrases.text(.dontKnow, lang), .primary, icon: "questionmark") { m.answer(.dontKnow) }
            card("123", StatusColor.info) { digits = "" }
                .accessibilityLabel(PartnerPhrases.text(.number, lang))
        }
    }

    private func card(_ title: String, _ tint: Color, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Ohne Farbunterscheidung (Einstellung „Ohne Farbe unterscheiden“): Symbol zusätzlich zur Farbe.
            (noColor && icon != nil ? Text(Image(systemName: icon!)) + Text(" ") + Text(title) : Text(title))
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    @ViewBuilder private func turnButton(_ color: Color) -> some View {
        if m.pushToTalk {
            holdButton(color)
        } else {
            Button { m.expectSpeaker(lang) } label: { turnLabel(color, active: expecting, icon: "mic.fill") }
                .buttonStyle(.plain)
                .disabled(ConversationLogic.turnLocked(speaking: m.speakingID != nil))   // Echo: nicht beim eigenen Sprechen
                .opacity(m.speakingID != nil ? 0.5 : 1)
                .accessibilityAddTraits(expecting ? .isSelected : [])
        }
    }

    private var turnTitle: String { isPartner ? PartnerPhrases.text(.nowYou, lang) : T("now_me") }

    private func turnLabel(_ color: Color, active: Bool, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(turnTitle)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .font(.title3.bold())
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(color, in: Capsule())
        // Der Zustand steht nicht nur in der Farbe: ein weißer Rand markiert den aktiven Zug.
        .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: active ? 3 : 0))
    }

    /// Push-to-talk je Hälfte (537): Halten = in dieser Sprache zuhören, Loslassen = Satz abschließen.
    private func holdButton(_ color: Color) -> some View {
        let held = m.pttHeld && m.expected == lang
        return turnLabel(color, active: held, icon: held ? "waveform" : "hand.tap.fill")
            .modifier(PushGesture(tapMode: m.pttTapMode, held: held,
                                  press: { m.holdToSpeak(lang) }, release: { m.pttRelease() }))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(turnTitle + ", " + T(held ? "ptt_release" : "ptt_hold"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { held ? m.pttRelease() : m.holdToSpeak(lang) }
    }
}

/// Ein Satz in einer Hälfte: Antipp spricht ihn erneut.
struct LineRow: View {
    @Environment(InterpreterModel.self) private var m
    let entry: Entry
    let text: String
    let own: Bool
    let lang: Lang
    let color: Color
    var scale: Double = 1
    @ScaledMetric(relativeTo: .body) private var scaledOwn: CGFloat = 17
    @ScaledMetric(relativeTo: .title2) private var scaledOther: CGFloat = 22
    private var scaledBase: CGFloat { own ? scaledOwn : scaledOther }

    var body: some View {
        let align: HorizontalAlignment = own ? .trailing : .leading
        let frameAlign: Alignment = own ? .trailing : .leading
        let tint: Color = own ? .secondary : color
        let roman: String? = !own && m.showRoman ? Romanizer.latin(text, lang) : nil
        Button { m.speak(entry) } label: {
            VStack(alignment: align, spacing: 2) {
                Text(ConversationLogic.highlighted(text))
                    .font(.system(size: scaledBase * scale, weight: own ? .regular : .bold))
                    .foregroundStyle(tint)
                    .multilineTextAlignment(own ? .trailing : .leading)
                    .spokenIn(lang.voiceLocale, text)   // Text steht in der Sprache dieser Hälfte
                RomanLine(text: roman)
            }
            .frame(maxWidth: .infinity, alignment: frameAlign)
        }
        .buttonStyle(.plain)
        .accessibilityHint(T("replay"))
    }
}

/// Zahlenfeld der Antwortkarte „Zahl“ (Preis, Uhrzeit, Anzahl) – in der gedrehten Hälfte des Gegenübers.
struct NumberPad: View {
    let digits: String
    let lang: Lang
    var onChange: (String) -> Void
    var onDone: () -> Void
    var onCancel: () -> Void

    private let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["0", "000", ".", "✓"]]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: onCancel) { Image(systemName: "xmark.circle.fill").font(.title2).minTapTarget() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(T("cancel"))
                Spacer()
                Text(digits.isEmpty ? PartnerPhrases.text(.number, lang) : NumberCard.spoken(digits, in: lang))
                    .font(.title.bold().monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .foregroundStyle(digits.isEmpty ? .secondary : .primary)
                Spacer()
                Button { onChange(String(digits.dropLast())) } label: { Image(systemName: "delete.left").font(.title2).minTapTarget() }
                    .buttonStyle(.plain).disabled(digits.isEmpty)
                    .accessibilityLabel(T("delete"))
            }
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { k in
                        Button { press(k) } label: {
                            Text(k).font(.title2.bold().monospacedDigit()).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(k == "✓" ? StatusColor.ok : .primary)
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
