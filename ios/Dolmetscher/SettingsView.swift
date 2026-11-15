// SettingsView.swift – Einstellungen: Sprache/Tempo, Übersetzung (offline/online), App-Sprache.
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
                Section(T("sec_speech")) {
                    Toggle(T("auto_speak"), isOn: $m.autoSpeak)
                    slider(T("silence"), value: $m.pauseSeconds, range: 0.4...2.0, step: 0.1,
                           text: String(format: "%.1f s", m.pauseSeconds))
                    slider(T("rate"), value: $m.rate, range: 0.5...1.5, step: 0.05,
                           text: String(format: "%.0f %%", m.rate * 100))
                    slider(T("volume"), value: $m.volume, range: 0.25...1.0, step: 0.05,
                           text: String(format: "%.0f %%", m.volume * 100))
                }
                Section {
                    if m.offlineReady {
                        Label(T("offline_ready"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button {
                            download = .init(source: Translator.language(.en), target: Translator.language(.th))
                        } label: { Label(T("offline_get"), systemImage: "arrow.down.circle") }
                    }
                    Toggle(T("online"), isOn: $m.allowOnline)
                } header: { Text(T("sec_translation")) } footer: { Text(T("online_note")) }
                Section {
                    Picker(T("ui_lang"), selection: $m.uiLang) {
                        Text("Deutsch").tag("de")
                        Text("English").tag("en")
                        Text("ไทย").tag("th")
                    }
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

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                        text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(text).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range, step: step)
        }
    }
}
