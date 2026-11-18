// SettingsView.swift – Einstellungen: Sprache/Tempo, Höflichkeit, Übersetzung (offline/online), Akku, App-Sprache.
import AVFoundation
import SwiftUI
import Translation

struct SettingsView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var whisper = WhisperStore.shared
    @State private var download: TranslationSession.Configuration?
    /// Verfügbarkeit je Sprache gegen die jeweils andere Seite des Paars.
    @State private var mineLevels: [Lang: LangLevel] = [:]
    @State private var partnerLevels: [Lang: LangLevel] = [:]
    @State private var confirmWipe = false

    var body: some View {
        @Bindable var m = m
        NavigationStack {
            Form {
                Section {
                    Picker(T("lang_mine"), selection: Binding(get: { m.pair.mine }, set: { setPair(mine: $0) })) {
                        ForEach(options(mineLevels, current: m.pair.mine, excluding: m.pair.partner)) { l in
                            Text(label(l, mineLevels[l])).tag(l)
                        }
                    }
                    Picker(T("lang_partner"), selection: Binding(get: { m.pair.partner }, set: { setPair(partner: $0) })) {
                        ForEach(options(partnerLevels, current: m.pair.partner, excluding: m.pair.mine)) { l in
                            Text(label(l, partnerLevels[l])).tag(l)
                        }
                    }
                } header: { Text(T("sec_langs")) } footer: { Text(T("lang_note")) }

                if m.features.thaiExtras {
                    Section {
                        Picker(T("politeness"), selection: $m.politeness) {
                            Text(T("pol_male")).tag(Politeness.male)
                            Text(T("pol_female")).tag(Politeness.female)
                            Text(T("pol_off")).tag(Politeness.off)
                        }
                    } header: { Text(T("sec_thai")) } footer: { Text(T("politeness_note")) }
                }

                Section(T("sec_speech")) {
                    Toggle(T("auto_speak"), isOn: $m.autoSpeak)
                    SpeechOptionsRows()
                    slider(T("silence"), value: $m.pauseSeconds, range: 0.4...2.0, step: 0.1,
                           text: String(format: "%.1f s", m.pauseSeconds))
                    slider(T("rate"), value: $m.rate, range: 0.5...1.5, step: 0.05,
                           text: String(format: "%.0f %%", m.rate * 100))
                    slider(T("volume"), value: $m.volume, range: 0.25...1.0, step: 0.05,
                           text: String(format: "%.0f %%", m.volume * 100))
                    Toggle(T("haptics"), isOn: $m.haptics)
                }

                Section {
                    voiceRow(m.pair.mine)
                    voiceRow(m.pair.partner)
                } header: { Text(T("voices")) } footer: { Text(T("voices_note")) }

                translationSection

                Section {
                    Toggle(T("whisper_use"), isOn: $whisper.enabled)
                    if whisper.enabled {
                        Picker(T("whisper_model"), selection: $whisper.selected) {
                            ForEach(whisper.choices, id: \.self) { v in
                                Text(WhisperCatalog.label(v) + Self.size(v)).tag(v)
                            }
                        }
                        .disabled(whisper.downloading)
                        if let p = whisper.progress {
                            HStack {
                                ProgressView(value: p)
                                Button(T("whisper_cancel")) { whisper.cancel() }.buttonStyle(.borderless)
                            }
                        } else if whisper.ready == whisper.selected {
                            Label(T("whisper_installed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            if let r = whisper.ready {
                                Label(T("whisper_installed") + ": " + WhisperCatalog.label(r), systemImage: "checkmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            Button { whisper.download() } label: {
                                Label(T("whisper_get") + Self.size(whisper.selected), systemImage: "arrow.down.circle")
                            }
                            if whisper.cellularPending {
                                Text(T("whisper_cellular")).font(.footnote).foregroundStyle(.orange)
                                Button(T("whisper_cellular_go")) { whisper.download(allowCellular: true) }
                            }
                        }
                        if let e = whisper.error { Text("⚠️ " + e).font(.footnote).foregroundStyle(.red) }
                        if whisper.ready != nil {
                            Button(T("whisper_delete"), role: .destructive) { whisper.deleteAll() }
                                .disabled(whisper.downloading)
                        }
                    }
                } header: { Text(T("sec_recognition")) } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T("whisper_note"))
                        if whisper.enabled { Text(T("whisper_wifi")) }
                        if whisper.enabled && m.background { Text(T("whisper_bg_warn")).foregroundStyle(.orange) }
                    }
                }

                listeningSection

                privacySection

                dataSection

                AboutSection()

                Section {
                    Picker(T("ui_lang"), selection: Binding(get: { m.uiLang }, set: { m.chooseUILang($0) })) {
                        ForEach(L10n.languages, id: \.self) { code in
                            // Eigenname der Sprache („Deutsch“, „ไทย“, „简体中文“)
                            Text(Locale(identifier: code).localizedString(forIdentifier: code)?.capitalized(with: Locale(identifier: code)) ?? code).tag(code)
                        }
                    }
                } footer: {
                    Text(T("shortcuts_note"))
                }
            }
            .navigationTitle(T("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { dismiss() } } }
            // Lädt die Sprachpakete über den Systemdialog; danach übersetzt die App offline.
            .translationTask(download) { session in
                try? await session.prepareTranslation()
                await m.refreshOffline()
            }
            .task { await m.refreshOffline() }
            .task(id: m.pair) {
                let p = m.pair
                mineLevels = await LangCheck.levels(with: p.partner)
                partnerLevels = await LangCheck.levels(with: p.mine)
            }
        }
    }

    private var listeningFooter: String {
        [T("listening_note"), T("sensitivity_note"), T("live_activity_note")].joined(separator: "\n")
    }

    private var listeningSection: some View {
        @Bindable var m = m
        return Section {
            Picker(T("auto_stop"), selection: $m.autoStopMinutes) {
                Text(T("never")).tag(0)
                Text("5 min").tag(5)
                Text("10 min").tag(10)
                Text("30 min").tag(30)
            }
            Toggle(T("background"), isOn: $m.background)
            Toggle(T("headset"), isOn: $m.headset)
            Picker(T("mic_input"), selection: $m.micUID) {
                Text(T("mic_auto")).tag(String?.none)
                ForEach(AVAudioSession.sharedInstance().availableInputs ?? [], id: \.uid) { port in
                    Text(port.portName).tag(Optional(port.uid))
                }
            }
            if #available(iOS 18.2, *) { Toggle(T("echo_cancel"), isOn: $m.echoCancel) }
            Toggle(T("thai_speaker"), isOn: $m.thaiOnSpeaker)
            Toggle(T("ptt"), isOn: $m.pushToTalk)
            if m.pushToTalk { Toggle(T("ptt_tap"), isOn: $m.pttTapMode) }
            Toggle(T("live_activity"), isOn: $m.liveActivity)
            Picker(T("sensitivity"), selection: $m.sensitivity) {
                Text(T("sens_quiet")).tag(Sensitivity.quiet)
                Text(T("sens_normal")).tag(Sensitivity.normal)
                Text(T("sens_loud")).tag(Sensitivity.loud)
            }
        } header: { Text(T("sec_listening")) } footer: { Text(listeningFooter) }
    }

    private var translationSection: some View {
        @Bindable var m = m
        return Section {
            NavigationLink { TravelPrepList().environment(\.inPanel, true) } label: { Label(T("prep_title"), systemImage: "checklist") }
            if m.offlineReady {
                Label(T("offline_ready"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button {
                    // Gleiche Konfiguration erneut anstoßen geht nur über invalidate().
                    if download == nil {
                        download = .init(source: Translator.language(m.pair.mine), target: Translator.language(m.pair.partner))
                    } else {
                        download?.invalidate()
                    }
                } label: { Label(T("offline_get"), systemImage: "arrow.down.circle") }
            }
            Toggle(T("online"), isOn: $m.allowOnline)
            Toggle(T("back_check"), isOn: $m.backCheck)
            Toggle(T("show_roman"), isOn: $m.showRoman)
        } header: { Text(T("sec_translation")) } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(T("online_off_note"))
                Text(T("back_check_note"))
            }
        }
    }

    private var privacySection: some View {
        @Bindable var m = m
        return Section {
            Picker(T("history_keep"), selection: $m.historyDays) {
                Text(T("history_none")).tag(0)
                Text(T("history_1d")).tag(1)
                Text(T("history_7d")).tag(7)
                Text(T("history_30d")).tag(30)
                Text(T("history_forever")).tag(-1)
            }
            if DeviceAuth.available || m.lockHistory {
                Toggle(T("lock_history"), isOn: lockBinding)
            }
            if m.lockInactive {
                Label(T("lock_inactive"), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Toggle(T("privacy_shield"), isOn: $m.privacyShield)
            Toggle(T("spotlight_favs"), isOn: $m.spotlight)
            Toggle(T("culture_hints"), isOn: $m.cultureHints)
            Toggle(T("summary_toggle"), isOn: $m.summaryEnabled)
            if m.summaryEnabled, let why = ConversationSummary.unavailableReason(for: m.pair.mine) {
                Text(why).font(.footnote).foregroundStyle(.secondary)
            }
            NavigationLink { PrivacyView() } label: { Label(T("privacy_overview"), systemImage: "hand.raised") }
        } header: { Text(T("sec_privacy")) } footer: { Text(T("history_note")) }
    }

    /// Alle Daten löschen (568) – mit Rückfrage; bei gesperrtem Verlauf erst Face ID.
    private var dataSection: some View {
        Section {
            Button(T("wipe_all"), role: .destructive) { confirmWipe = true }
                .confirmationDialog(T("wipe_all"), isPresented: $confirmWipe, titleVisibility: .visible) {
                    Button(T("wipe_all"), role: .destructive, action: wipe)
                    Button(T("cancel"), role: .cancel) {}
                } message: { Text(T("wipe_confirm")) }
        } footer: { Text(T("wipe_note")) }
    }

    private func wipe() {
        Task {
            if m.lockHistory, DeviceAuth.available, !(await DeviceAuth.authenticate(reason: T("lock_reason"))) { return }
            m.wipeAll()
            Haptics.success()
            dismiss()
        }
    }

    /// Ein- und Ausschalten nur nach erfolgreicher Prüfung (sonst hebt jeder die Sperre auf).
    private var lockBinding: Binding<Bool> {
        Binding(get: { m.lockHistory }, set: { (on: Bool) in
            Task { if await DeviceAuth.authenticate(reason: T("lock_reason")) { m.lockHistory = on } }
        })
    }

    private func setPair(mine: Lang? = nil, partner: Lang? = nil) {
        var p = m.pair
        if let mine { p.mine = mine }
        if let partner { p.partner = partner }
        guard p.mine != p.partner else { return }
        download = nil
        m.pair = p
    }

    /// Auswahl: alles außer „nicht verfügbar“ – die aktuelle Sprache bleibt immer drin. Solange die Prüfung läuft,
    /// nur die aktuelle.
    private func options(_ levels: [Lang: LangLevel], current: Lang, excluding other: Lang) -> [Lang] {
        if levels.isEmpty { return [current] }
        return Lang.all.filter { $0 != other && ($0 == current || (levels[$0] ?? .unavailable) != .unavailable) }
    }

    private func label(_ l: Lang, _ level: LangLevel?) -> String {
        let name = "\(l.flag) \(l.native)"
        switch level {
        case .needsDownload: return name + " ⬇︎ " + T("lang_download")
        case .onlineOnly: return name + " 🌐 " + T("lang_online_only")
        case .unavailable: return name + " – " + T("lang_unavailable")
        default: return name
        }
    }

    private static func size(_ variant: String) -> String {
        WhisperCatalog.sizeMB(variant).map { " (~\($0) MB)" } ?? ""
    }

    private func voiceRow(_ lang: Lang) -> some View {
        let v = Speaker.voice(lang)
        let q: String
        switch v?.quality {
        case .premium: q = "Premium"
        case .enhanced: q = T("voice_enhanced")
        default: q = T("voice_basic")
        }
        return HStack {
            Text("\(LangStyle.flag(lang)) \(v?.name ?? "–")")
            Spacer()
            Text(q).foregroundStyle(v?.quality == .default ? Color.orange : Color.secondary)
            // Probehören: so klingt die Stimme, die die App für diese Sprache nimmt.
            Button { m.announce(PartnerPhrases.text(.nowYou, lang), lang: lang) } label: { Image(systemName: "speaker.wave.2.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel(T("replay"))
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                        text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(text).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(text)
        }
    }
}

/// Info (572): Version, Datenschutzerklärung, Lizenzen, Quellcode.
private struct AboutSection: View {
    private static let repo = "https://github.com/Pschmetzer/en-th-dolmetscher"

    private var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "?"
        let b = i?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        Section {
            LabeledContent(T("app_version"), value: version)
            link("privacy_policy", "docs/DATENSCHUTZ.md", icon: "hand.raised")
            link("licenses", "docs/LIZENZEN.md", icon: "doc.text")
            link("source_code", "", icon: "chevron.left.forwardslash.chevron.right")
            link("support", "issues", icon: "questionmark.bubble")
        } header: { Text(T("sec_about")) }
    }

    private func link(_ key: String, _ path: String, icon: String) -> some View {
        let tail = path.isEmpty ? "" : (path.hasPrefix("docs/") ? "/blob/main/" + path : "/" + path)
        return Link(destination: URL(string: Self.repo + tail)!) { Label(T(key), systemImage: icon) }
    }
}

/// Vorlesen je Richtung (589) und „Langsam und deutlich“ (906) – eigene Ansicht, hält den Typprüfer klein.
private struct SpeechOptionsRows: View {
    @Environment(InterpreterModel.self) private var m

    var body: some View {
        @Bindable var m = m
        let mine = String(format: T("auto_speak_mine"), m.pair.mine.name(in: m.uiLang))
        return Group {
            if m.autoSpeak { Toggle(mine, isOn: $m.autoSpeakMine) }
            Toggle(T("clear_speech"), isOn: $m.clearSpeech)
        }
    }
}
