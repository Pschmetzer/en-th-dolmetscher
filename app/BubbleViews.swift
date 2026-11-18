// BubbleViews.swift – Sprechblase (mit Platzhalter, Konfidenz, Umschrift, Details) und Korrektur-Dialog.
import SwiftUI

/// Eine Blase beobachtet das Modell nicht selbst: Sie bekommt nur die Werte, die sie zeigt, und ist
/// `Equatable`. So zeichnet ein Statuswechsel (Pegel, „Höre …“, Rückstand) nicht jede sichtbare Blase neu,
/// sondern nur die, deren Inhalt sich geändert hat.
struct Bubble: View, Equatable {
    let m: EngineModel           // nur für Aktionen (vorlesen, korrigieren), nicht beobachtet
    let u: Utterance
    let scale: Double
    let playing: Bool
    let running: Bool
    let twoPerson: Bool
    /// Sprachpaar (Nr. 7): Seite und Farbe hängen an den globalen `Langs`; ohne diesen Wert bliebe die Blase nach einem Paarwechsel stehen.
    var pairKey = ""
    var onCorrect: (Utterance) -> Void = { _ in }
    @State private var hovering = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (a: Bubble, b: Bubble) -> Bool {
        a.u == b.u && a.scale == b.scale && a.playing == b.playing && a.running == b.running
            && a.twoPerson == b.twoPerson && a.pairKey == b.pairKey
    }

    var body: some View {
        if u.pending { PlaceholderBubble(u: u, scale: scale) } else { content }
    }

    private var en: Bool { Langs.isMine(u.lang) }   // meine Seite (Standard: Englisch)
    private var canReassign: Bool { twoPerson && u.source != "phrase" && u.source != "edit" }
    private func reassign() { m.reassign(u, role: Langs.reassignRole(u.lang)) }

    /// Solange diese Blase vorgelesen wird: deutlicher Abbrechen-Knopf direkt an der Blase.
    private var stopButton: some View {
        Button { m.stopSpeaking() } label: {
            Label(L.t("cancel"), systemImage: "stop.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(.white)
                .background(Color.red, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(8)
        .help(L.t("stop_speaking"))
        .accessibilityLabel(L.t("stop_speaking"))
    }

    /// Vorlesen- und Korrektur-Knöpfe: immer erreichbar (Tastatur-Fokus, Touchpad ohne Hover), blass im
    /// Ruhezustand, deutlich bei Maus-Hover. Vorlesen hat einen eigenen Knopf: ein Klick in den Text markiert
    /// nur (textSelection) und liest nicht versehentlich laut vor.
    private var quickActions: some View {
        HStack(spacing: 2) {
            Button { m.replay(u) } label: { Image(systemName: "play.fill") }
                .help(L.t("read_aloud")).accessibilityLabel(L.t("read_aloud"))
            if canCorrect {
                Button { onCorrect(u) } label: { Image(systemName: "pencil") }
                    .help(L.t("correct")).accessibilityLabel(L.t("correct"))
            }
            if canCorrect && canReassign {
                Button(action: reassign) { Image(systemName: "arrow.left.arrow.right") }
                    .help(L.reassign(Langs.reassignRole(u.lang)))
                    .accessibilityLabel(L.reassign(Langs.reassignRole(u.lang)))
            }
            Button { copy(u.out) } label: { Image(systemName: "doc.on.doc") }
                .help(L.t("copy_translation")).accessibilityLabel(L.t("copy_translation"))
        }
        .buttonStyle(QuickActionStyle())
        .font(.system(size: 15))
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35)))
        .padding(8)
        .opacity(hovering ? 1 : 0.85)      // Nr. 381: auch im Ruhezustand gut lesbar
    }
    private var helpText: String {
        (u.lowConfidence ? L.t("low_conf") + " – " + L.t("click_replay") : L.t("click_replay"))
            + "\n" + u.date.formatted(date: .omitted, time: .standard)
    }
    /// VoiceOver-Text; Thai-Abschnitte tragen die Sprachkennung "th".
    private var a11yText: AttributedString {
        var parts: [(String, String?)] = [("\(LangStyle.name(u.lang)): ", nil), (u.text, u.lang)]
        if u.translated {
            parts += [(". \(LangStyle.name(u.to)): ", nil), (u.out, u.to)]
        } else {
            parts.append((". " + L.t("not_translated"), nil))
        }
        var tail = ""
        if let who = u.speaker ?? u.role, !who.isEmpty { parts.insert((who + ": ", nil), at: 0) }
        if u.numWarn { tail += ". " + L.t("num_warn") }
        if u.provider == "mymemory" { tail += ". " + L.t("weak_mt") }
        if u.lowConfidence { tail += ". " + L.t("low_conf") }
        if u.skipped { tail += ". " + L.t("not_spoken") }
        if u.cutOff { tail += ". " + L.t("cut_off") }
        if !tail.isEmpty { parts.append((tail, nil)) }
        return a11yAttributed(parts)
    }

    /// VoiceOver-Aktionen der Blase (als Liste, damit der Ausdruck für den Compiler klein bleibt).
    private var a11yActions: [(String, () -> Void)] {
        [
            (L.t("stop_speaking"), { m.stopSpeaking() }),
            (L.t("read_aloud"), { m.replay(u) }),
            (L.t("copy_translation"), { copy(u.out) }),
            (L.t("correct"), { if canCorrect { onCorrect(u) } }),
            (L.reassign(Langs.reassignRole(u.lang)), { if canCorrect && canReassign { reassign() } }),   // Nr. 382
            (L.t("alt_reading"), { if canCorrect, let alt = u.alts.first { m.retranslate(u, text: alt) } }),
            (L.t("save_phrase"), { saveQuickPhrase(u.text) }),
            (L.t("big_text"), { NotificationCenter.default.post(name: .showBigText, object: u.id) }),
            (L.t("copy_both"), { copy(u.text + "\n" + u.out) }),
            (L.t("delete_bubble"), { m.deleteItem(u) }),
        ]
    }

    private var content: some View {
        VStack(alignment: en ? .leading : .trailing, spacing: 6) {
            BubbleHeader(u: u, scale: scale, playing: playing)
            BubbleMain(u: u, scale: scale)
            BubbleFooter(u: u, scale: scale, onCorrect: canCorrect ? { onCorrect(u) } : nil,
                         onReplay: { m.replay(u) })
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: en ? .leading : .trailing)
        .background(LangStyle.color(u.lang).opacity(playing ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if u.lowConfidence {
                RoundedRectangle(cornerRadius: 14).strokeBorder(LangStyle.warning, lineWidth: 2)
            }
        }
        .overlay(alignment: en ? .topTrailing : .topLeading) {
            if playing {
                stopButton                       // läuft gerade: sofort abbrechen
            } else {
                quickActions                     // ▶ Vorlesen (eigener Knopf statt Klick auf die ganze Blase)
            }
        }
        .onHover { h in
            if reduceMotion { hovering = h } else { withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        }
        .overlay(alignment: .topTrailing) {
            if copied {
                let badge: some View = Text(L.t("copied"))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .padding(6)
                let appear: AnyTransition = reduceMotion ? .identity : .opacity
                badge.transition(appear).accessibilityHidden(true)
            }
        }
        .help(helpText)
        .contextMenu { menu }
        // Tastatur (Nr. 354): Tab erreicht die Blase; Enter liest vor, E korrigiert, ⌘C kopiert die Übersetzung
        .focusable()
        .onKeyPress(.return) { if playing { m.stopSpeaking() } else { m.replay(u) }; return .handled }
        .onKeyPress(.escape) { guard playing else { return .ignored }; m.stopSpeaking(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "eEcC")) { press in
            switch press.characters.lowercased() {
            case "e" where canCorrect: onCorrect(u); return .handled
            case "c" where press.modifiers.isEmpty: copy(u.out); return .handled
            default: return .ignored
            }
        }
        .onCopyCommand { [NSItemProvider(object: u.out as NSString)] }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11yText))
        .accessibilityHint(playing ? L.t("stop_speaking") : L.t("click_replay") + ". " + L.t("bubble_keys"))
        .modifier(A11yActionList(items: a11yActions))
    }

    /// Nr. 33: sichtbare und hörbare Rückmeldung beim Kopieren
    private func copy(_ s: String) {
        copyToPasteboard(s)
        Announcer.post(L.t("copied"))
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { copied = false }
    }

    private func saveQuickPhrase(_ s: String) {
        let ud = UserDefaults.standard
        let cur = ud.string(forKey: Prefs.quickPhrases) ?? Prefs.pairDefaults
        guard !Prefs.phrases(cur).contains(s) else { return }
        ud.set(cur.isEmpty ? s : cur + "\n" + s, forKey: Prefs.quickPhrases)
    }

    private var canCorrect: Bool { u.uid != nil && running }

    @ViewBuilder private var menu: some View {
        Button(L.t("copy_translation")) { copy(u.out) }
        Button(L.t("copy_original")) { copy(u.text) }
        Button(L.t("copy_both")) { copy(u.text + "\n" + u.out) }
        Divider()
        Button(L.t("correct")) { onCorrect(u) }.disabled(!canCorrect)
        if canReassign {
            Button(L.reassign(Langs.reassignRole(u.lang)), action: reassign).disabled(!canCorrect)
        }
        ForEach(Array(u.alts.enumerated()), id: \.offset) { _, alt in
            Button(L.t("alt_reading") + ": " + alt) { m.retranslate(u, text: alt) }.disabled(!canCorrect)
        }
        Button(L.t("save_phrase")) { saveQuickPhrase(u.text) }
        Button(L.t("read_aloud")) { m.replay(u) }
        Button(L.t("stop_speaking")) { m.stopSpeaking() }
        Divider()
        Button(L.t("big_text")) { NotificationCenter.default.post(name: .showBigText, object: u.id) }
        ShareLink(item: u.out.isEmpty ? u.text : u.text + "\n" + u.out) { Label(L.t("share"), systemImage: "square.and.arrow.up") }
        Divider()
        Button(L.t("delete_bubble"), role: .destructive) { m.deleteItem(u) }   // Nr. 383
    }
}

/// Nr. 381: Trefferfläche mindestens 24 × 24 pt, deutliche Rückmeldung beim Drücken.
private struct QuickActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 26, minHeight: 26)
            .contentShape(Rectangle())
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// Flagge, Sprechername, Originaltext (+ Umschrift bei Thai).
private struct BubbleHeader: View {
    let u: Utterance
    let scale: Double
    let playing: Bool
    @AppStorage(Prefs.translit) private var translit = true

    private var line: String {
        let roleName: String? = u.role.map { L.t($0 == "me" ? "role_me" : "role_other") }
        let who: String = (u.speaker ?? roleName).map { "\($0): " } ?? ""
        let original: String = u.translated ? u.text : L.t("not_translated")
        return LangStyle.flag(u.lang) + " " + who + original
    }

    var body: some View {
        let en = Langs.isMine(u.lang)
        VStack(alignment: en ? .leading : .trailing, spacing: 2) {
            HStack(spacing: 6) {
                if !en { Spacer(minLength: 0) }
                Text(line)
                    .font(.system(size: 15 * scale)).foregroundStyle(.secondary)
                    .multilineTextAlignment(en ? .leading : .trailing)
                    .textSelection(.enabled)
                if playing { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary).accessibilityHidden(true) }
                if en { Spacer(minLength: 0) }
            }
            if translit && u.translated, let latin = u.textLatin {
                Text(latin)
                    .font(.system(size: max(12, 12 * scale))).italic().foregroundStyle(.secondary)
                    .multilineTextAlignment(en ? .leading : .trailing)
            }
        }
    }
}

/// Übersetzung groß (+ Umschrift bei Thai).
private struct BubbleMain: View {
    let u: Utterance
    let scale: Double
    @AppStorage(Prefs.translit) private var translit = true
    @AppStorage("backTranslate") private var showBack = false

    var body: some View {
        let en = Langs.isMine(u.lang)
        VStack(alignment: en ? .leading : .trailing, spacing: 2) {
            Text(u.out)
                .font(.system(size: 30 * scale, weight: .semibold))
                .foregroundStyle(u.translated ? LangStyle.color(u.to) : .primary)
                .multilineTextAlignment(en ? .leading : .trailing)
                .textSelection(.enabled)
            if translit, let latin = u.translated ? u.outLatin : u.textLatin {
                Text(latin)
                    .font(.system(size: 14 * scale)).italic().foregroundStyle(.secondary)
                    .multilineTextAlignment(en ? .leading : .trailing)
            }
            if showBack, let back = u.back {   // Rückübersetzung: klein, zur Kontrolle
                Text("↩︎ " + back)
                    .font(.system(size: 12 * scale)).foregroundStyle(.secondary)
                    .multilineTextAlignment(en ? .leading : .trailing)
                    .textSelection(.enabled)
                    .accessibilityLabel(L.t("back_translate") + ": " + back)
            }
        }
    }
}

/// „nicht vorgelesen“ und (optional) Dienst + Zeiten.
private struct BubbleFooter: View {
    let u: Utterance
    let scale: Double
    var onCorrect: (() -> Void)? = nil
    var onReplay: (() -> Void)? = nil
    @AppStorage(Prefs.showDetails) private var showDetails = false

    private static func sec(_ v: Double) -> String { fmtSeconds(v) }

    private var details: String {
        var parts: [String] = []
        if let p = u.provider, !p.isEmpty { parts.append(p) }
        if u.stt > 0 { parts.append(L.t("stt_short") + " " + Self.sec(u.stt)) }
        if u.tr > 0 { parts.append(L.t("tr_short") + " " + Self.sec(u.tr)) }
        if let r = u.readyS { parts.append(L.t("ready_short") + " " + Self.sec(r)) }
        if let l = u.latency { parts.append(L.t("to_sound") + " " + Self.sec(l)) }
        else if let f = u.firstSound { parts.append(L.t("first_sound") + " " + Self.sec(f)) }
        if let lp = u.lp { parts.append("lp " + fmtNumber(lp)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let showD = showDetails && !details.isEmpty
        if u.skipped || u.cutOff || u.lowConfidence || u.numWarn || u.provider == "mymemory" || showD {
            HStack(spacing: 10) {
                if !Langs.isMine(u.lang) { Spacer(minLength: 0) }
                if u.skipped {
                    Label(L.t("not_spoken"), systemImage: "speaker.slash")
                        .foregroundStyle(.secondary)
                }
                if u.cutOff && !u.skipped {
                    Label(L.t("cut_off"), systemImage: "speaker.badge.exclamationmark")
                        .foregroundStyle(LangStyle.warning)
                    if let onReplay {
                        Button(action: onReplay) { Label(L.t("speak_again"), systemImage: "arrow.counterclockwise") }
                            .buttonStyle(.borderless)
                            .help(L.t("speak_again_help"))
                    }
                }
                if u.numWarn {
                    Label(L.t("num_warn"), systemImage: "number.circle").foregroundStyle(LangStyle.warning)
                }
                if u.provider == "mymemory" {
                    Label(L.t("weak_mt"), systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                }
                if u.lowConfidence {
                    Label(L.t("low_conf"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(LangStyle.warning)
                    if let onCorrect {
                        Button(action: onCorrect) { Label(L.t("correct"), systemImage: "pencil") }
                            .buttonStyle(.borderless)
                    }
                }
                if showD { Text(details).foregroundStyle(.secondary).monospacedDigit() }
                if Langs.isMine(u.lang) { Spacer(minLength: 0) }
            }
            .font(.system(size: max(12, 11 * scale)))
        }
    }
}

/// Platzhalter, solange gesprochen bzw. erkannt/übersetzt wird – mit vorläufigem Text (`partial`).
private struct PlaceholderBubble: View {
    let u: Utterance
    let scale: Double
    @AppStorage(Prefs.translit) private var translit = true

    private var partial: String? {
        guard let p = u.partial, !p.isEmpty else { return nil }
        return p
    }

    var body: some View {
        if let p = partial { partialBody(p) } else { plainBody }
    }

    private var plainBody: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L.t("translating_placeholder"))
                .font(.system(size: 17 * scale)).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("translating_placeholder"))
    }

    /// Teiltext (`partial`, kursiv) oder schon fertig erkannter Originaltext (`heard`, aufrecht, mit Umschrift),
    /// während die Übersetzung noch läuft.
    private func partialBody(_ p: String) -> some View {
        let en = Langs.isMine(u.lang)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !en { Spacer(minLength: 0) }
            ProgressView().controlSize(.small)
            Text(LangStyle.flag(u.lang)).accessibilityHidden(true)
            VStack(alignment: en ? .leading : .trailing, spacing: 2) {
                if u.heard {
                    Text(p)
                        .font(.system(size: 17 * scale)).foregroundStyle(.primary)
                        .multilineTextAlignment(en ? .leading : .trailing)
                        .textSelection(.enabled)
                    if translit, let latin = u.heardLatin, !latin.isEmpty {
                        Text(latin)
                            .font(.system(size: max(12, 12 * scale))).italic().foregroundStyle(.secondary)
                            .multilineTextAlignment(en ? .leading : .trailing)
                    }
                } else {
                    Text(p)
                        .font(.system(size: 17 * scale)).italic().foregroundStyle(.secondary)
                        .multilineTextAlignment(en ? .leading : .trailing)
                }
            }
            if en { Spacer(minLength: 0) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: en ? .leading : .trailing)
        .background(LangStyle.color(u.lang).opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11yAttributed([(L.t(u.heard ? "heard_a11y" : "partial_a11y") + ": ", nil), (p, u.lang)])))
    }
}

/// Erkannten Text korrigieren → Engine übersetzt neu und liest vor (retranslate).
struct CorrectSheet: View {
    @EnvironmentObject var m: EngineModel
    @Environment(\.dismiss) private var dismiss
    let u: Utterance
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("correct_title")).font(.title2.bold())
            HStack(spacing: 6) {
                Text(LangStyle.flag(u.lang)).accessibilityHidden(true)
                Text(LangStyle.name(u.lang))
            }.foregroundStyle(.secondary)
            TextField(L.t("correct_title"), text: $text, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .onSubmit(submit)
            Text(L.t("correct_hint")).font(.callout).foregroundStyle(.secondary)
            if !u.alts.isEmpty {
                // Nr. 384: andere Lesarten der Erkennung als Vorschläge (vorher nur im Kontextmenü)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("alt_suggestions")).font(.callout.bold())
                    ForEach(Array(u.alts.enumerated()), id: \.offset) { _, alt in
                        Button { text = alt } label: {
                            Label(alt, systemImage: "text.badge.checkmark").multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.link)
                        .accessibilityLabel(L.t("alt_reading") + ": " + alt)
                    }
                }
            }
            HStack {
                Spacer()
                Button(L.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L.t("translate_again"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || !m.engineReady)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { text = u.text }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func submit() {
        guard !trimmed.isEmpty, m.engineReady else { return }
        m.retranslate(u, text: trimmed)
        dismiss()
    }
}

/// Hängt eine Liste benannter VoiceOver-Aktionen an eine Ansicht.
private struct A11yActionList: ViewModifier {
    let items: [(String, () -> Void)]
    func body(content: Content) -> some View {
        items.reduce(AnyView(content)) { v, a in AnyView(v.accessibilityAction(named: a.0, a.1)) }
    }
}
