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

                Section {
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
                } header: { Text(T("sec_translation")) } footer: { Text(T("online_off_note")) }

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

                Section {
                    Picker(T("auto_stop"), selection: $m.autoStopMinutes) {
                        Text(T("never")).tag(0)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("30 min").tag(30)
                    }
                    Toggle(T("background"), isOn: $m.background)
                    Toggle(T("headset"), isOn: $m.headset)
                    Toggle(T("thai_speaker"), isOn: $m.thaiOnSpeaker)
                } header: { Text(T("sec_listening")) } footer: { Text(T("listening_note")) }

                Section {
                    Picker(T("history_keep"), selection: $m.historyDays) {
                        Text(T("history_none")).tag(0)
                        Text(T("history_1d")).tag(1)
                        Text(T("history_7d")).tag(7)
                        Text(T("history_30d")).tag(30)
                        Text(T("history_forever")).tag(-1)
                    }
                } header: { Text(T("sec_privacy")) } footer: { Text(T("history_note")) }

                Section {
                    Picker(T("ui_lang"), selection: $m.uiLang) {
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
