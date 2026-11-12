// BubbleViews.swift – Sprechblase (mit Platzhalter, Konfidenz, Umschrift, Details) und Korrektur-Dialog.
import SwiftUI

struct Bubble: View {
    @EnvironmentObject var m: EngineModel
    let u: Utterance
    let scale: Double
    var onCorrect: (Utterance) -> Void = { _ in }

    var body: some View {
        if u.pending { PlaceholderBubble(u: u, scale: scale) } else { content }
    }

    private var en: Bool { u.lang == "en" }
    private var playing: Bool { m.replayingID == u.id || (u.uid != nil && m.speakingIDs.contains(u.uid!)) }
    private var helpText: String {
        (u.lowConfidence ? L.t("low_conf") + " – " + L.t("click_replay") : L.t("click_replay"))
            + "\n" + u.date.formatted(date: .omitted, time: .standard)
    }
    private var a11yText: String {
        var s = "\(LangStyle.name(u.lang)): \(u.text). "
        s += u.translated ? "\(LangStyle.name(u.to)): \(u.out)" : L.t("not_translated")
        if u.lowConfidence { s += ". " + L.t("low_conf") }
        if u.skipped { s += ". " + L.t("not_spoken") }
        return s
    }

    private var content: some View {
        VStack(alignment: en ? .leading : .trailing, spacing: 6) {
            BubbleHeader(u: u, scale: scale, playing: playing)
            BubbleMain(u: u, scale: scale)
            BubbleFooter(u: u, scale: scale, onCorrect: canCorrect ? { onCorrect(u) } : nil)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: en ? .leading : .trailing)
        .background(LangStyle.color(u.lang).opacity(playing ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if u.lowConfidence {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { m.replay(u) }
        .help(helpText)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L.t("click_replay"))
        .accessibilityAction(named: L.t("read_aloud")) { m.replay(u) }
        .accessibilityAction(named: L.t("copy_translation")) { copyToPasteboard(u.out) }
        .accessibilityAction(named: L.t("correct")) { if canCorrect { onCorrect(u) } }
    }

    private func saveQuickPhrase(_ s: String) {
        let ud = UserDefaults.standard
        let cur = ud.string(forKey: Prefs.quickPhrases) ?? Prefs.defaultPhrases
        guard !Prefs.phrases(cur).contains(s) else { return }
        ud.set(cur.isEmpty ? s : cur + "\n" + s, forKey: Prefs.quickPhrases)
    }

    private var canCorrect: Bool { u.uid != nil && m.running }

    @ViewBuilder private var menu: some View {
        Button(L.t("copy_translation")) { copyToPasteboard(u.out) }
        Button(L.t("copy_original")) { copyToPasteboard(u.text) }
        Button(L.t("copy_both")) { copyToPasteboard(u.text + "\n" + u.out) }
        Divider()
        Button(L.t("correct")) { onCorrect(u) }.disabled(!canCorrect)
        ForEach(Array(u.alts.enumerated()), id: \.offset) { _, alt in
            Button(L.t("alt_reading") + ": " + alt) { m.retranslate(u, text: alt) }.disabled(!canCorrect)
        }
        if u.lang == "en" {
            Button(L.t("save_phrase")) { saveQuickPhrase(u.text) }
        }
        Button(L.t("read_aloud")) { m.replay(u) }
        Button(L.t("stop_speaking")) { m.stopSpeaking() }
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
        let en = u.lang == "en"
        VStack(alignment: en ? .leading : .trailing, spacing: 2) {
            HStack(spacing: 6) {
                if !en { Spacer(minLength: 0) }
                Text(line)
                    .font(.system(size: 15 * scale)).foregroundStyle(.secondary)
                    .multilineTextAlignment(en ? .leading : .trailing)
                if playing { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary).accessibilityHidden(true) }
                if en { Spacer(minLength: 0) }
            }
            if translit && u.translated, let latin = u.textLatin {
                Text(latin)
                    .font(.system(size: 12 * scale)).italic().foregroundStyle(.tertiary)
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

    var body: some View {
        let en = u.lang == "en"
        VStack(alignment: en ? .leading : .trailing, spacing: 2) {
            Text(u.out)
                .font(.system(size: 30 * scale, weight: .semibold))
                .foregroundStyle(u.translated ? LangStyle.color(u.to) : .primary)
                .multilineTextAlignment(en ? .leading : .trailing)
            if translit, let latin = u.translated ? u.outLatin : u.textLatin {
                Text(latin)
                    .font(.system(size: 14 * scale)).italic().foregroundStyle(.secondary)
                    .multilineTextAlignment(en ? .leading : .trailing)
            }
        }
    }
}

/// „nicht vorgelesen“ und (optional) Dienst + Zeiten.
private struct BubbleFooter: View {
    let u: Utterance
    let scale: Double
    var onCorrect: (() -> Void)? = nil
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
        if let lp = u.lp { parts.append(String(format: "lp %.2f", lp)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let showD = showDetails && !details.isEmpty
        if u.skipped || u.lowConfidence || u.numWarn || u.provider == "mymemory" || showD {
            HStack(spacing: 10) {
                if u.lang != "en" { Spacer(minLength: 0) }
                if u.skipped {
                    Label(L.t("not_spoken"), systemImage: "speaker.slash")
                        .foregroundStyle(.secondary)
                }
                if u.numWarn {
                    Label(L.t("num_warn"), systemImage: "number.circle").foregroundStyle(Color.orange)
                }
                if u.provider == "mymemory" {
                    Label(L.t("weak_mt"), systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                }
                if u.lowConfidence {
                    Label(L.t("low_conf"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                    if let onCorrect {
                        Button(action: onCorrect) { Label(L.t("correct"), systemImage: "pencil") }
                            .buttonStyle(.borderless)
                    }
                }
                if showD { Text(details).foregroundStyle(.tertiary).monospacedDigit() }
                if u.lang == "en" { Spacer(minLength: 0) }
            }
            .font(.system(size: 11 * scale))
        }
    }
}

/// Platzhalter, solange gesprochen bzw. erkannt/übersetzt wird – mit vorläufigem Text (`partial`).
private struct PlaceholderBubble: View {
    let u: Utterance
    let scale: Double

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

    private func partialBody(_ p: String) -> some View {
        let en = u.lang != "th"
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !en { Spacer(minLength: 0) }
            ProgressView().controlSize(.small)
            Text(LangStyle.flag(u.lang) + " " + p)
                .font(.system(size: 17 * scale)).italic().foregroundStyle(.secondary)
                .multilineTextAlignment(en ? .leading : .trailing)
            if en { Spacer(minLength: 0) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: en ? .leading : .trailing)
        .background(LangStyle.color(u.lang).opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("partial_a11y") + ": " + p)
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
            Text(LangStyle.flag(u.lang) + " " + LangStyle.name(u.lang)).foregroundStyle(.secondary)
            TextField(L.t("correct_title"), text: $text, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .onSubmit(submit)
            Text(L.t("correct_hint")).font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L.t("translate_again"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || !m.running)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { text = u.text }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func submit() {
        guard !trimmed.isEmpty, m.running else { return }
        m.retranslate(u, text: trimmed)
        dismiss()
    }
}
