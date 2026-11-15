// SettingsView.swift – Einstellungen: Sprache/Tempo, Höflichkeit, Übersetzung (offline/online), Akku, App-Sprache.
import AVFoundation
import SwiftUI
import Translation

struct SettingsView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        @Bindable var m = m
        NavigationStack {
            Form {
                Section {
                    Picker(T("politeness"), selection: $m.politeness) {
                        Text(T("pol_male")).tag(Politeness.male)
                        Text(T("pol_female")).tag(Politeness.female)
                        Text(T("pol_off")).tag(Politeness.off)
                    }
                } header: { Text(T("sec_thai")) } footer: { Text(T("politeness_note")) }

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
                    voiceRow(.en)
                    voiceRow(.th)
                } header: { Text(T("voices")) } footer: { Text(T("voices_note")) }

                Section {
                    if m.offlineReady {
                        Label(T("offline_ready"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button {
                            // Gleiche Konfiguration erneut anstoßen geht nur über invalidate().
                            if download == nil {
                                download = .init(source: Translator.language(.en), target: Translator.language(.th))
                            } else {
                                download?.invalidate()
                            }
                        } label: { Label(T("offline_get"), systemImage: "arrow.down.circle") }
                    }
                    Toggle(T("online"), isOn: $m.allowOnline)
                } header: { Text(T("sec_translation")) } footer: { Text(T("online_note")) }

                Section {
                    Picker(T("auto_stop"), selection: $m.autoStopMinutes) {
                        Text(T("never")).tag(0)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("30 min").tag(30)
                    }
                    Toggle(T("background"), isOn: $m.background)
                    Toggle(T("headset"), isOn: $m.headset)
                } header: { Text(T("sec_listening")) } footer: { Text(T("listening_note")) }

                Section {
                    Picker(T("ui_lang"), selection: $m.uiLang) {
                        Text("Deutsch").tag("de")
                        Text("English").tag("en")
                        Text("ไทย").tag("th")
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
        }
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
