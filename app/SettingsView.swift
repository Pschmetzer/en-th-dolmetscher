// SettingsView.swift – Einstellungsfenster (⌘,).
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false

    var body: some View {
        Form {
            Section("Übersetzung") {
                Toggle("🇬🇧 → 🇹🇭  Englisch ins Thai übersetzen", isOn: $m.trEN)
                    .help("Aus = Englisch bleibt Englisch")
                    .accessibilityLabel("Englisch ins Thai übersetzen")
                Toggle("🇹🇭 → 🇬🇧  Thai ins Englische übersetzen", isOn: $m.trTH)
                    .help("Aus = Thai bleibt Thai")
                    .accessibilityLabel("Thai ins Englische übersetzen")
                Picker("Spracherkennung", selection: $m.lang) {
                    Text("Automatisch").tag("auto")
                    Text("🇬🇧 nur Englisch").tag("en")
                    Text("🇹🇭 nur Thai").tag("th")
                }
                .help("Sprache fest einstellen, falls Auto falsch erkennt")
                .accessibilityLabel("Spracherkennung")
            }
            Section("Stimme") {
                Toggle("Übersetzung vorlesen", isOn: $m.speak)
                    .accessibilityLabel("Übersetzung vorlesen")
                Picker("Höflichkeitspartikel (Thai)", selection: $m.polite) {
                    Text("ครับ – männlich").tag("krub")
                    Text("ค่ะ – weiblich").tag("ka")
                }
                .accessibilityLabel("Thai-Höflichkeitspartikel: männlich krub oder weiblich ka")
            }
            Section {
                Picker("Erkennungsmodell", selection: $m.model) {
                    Text("Schnell (small)").tag("small")
                    Text("Normal (medium)").tag("medium")
                    Text("Beste (Englisch+)").tag("best")
                }
                .disabled(m.active)
                .accessibilityLabel("Erkennungsmodell")
            } header: { Text("Modell") } footer: {
                Text(m.active ? "Wirkt erst nach Stopp und erneutem Start." : "Größere Modelle erkennen genauer, brauchen aber länger.")
                    .foregroundStyle(.secondary)
            }
            Section("Anzeige") {
                HStack {
                    Text("Schriftgröße")
                    Slider(value: $scale, in: Prefs.fontRange, step: 0.1)
                        .accessibilityLabel("Schriftgröße")
                        .accessibilityValue("\(Int(scale * 100)) Prozent")
                    Text("\(Int(scale * 100)) %").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Toggle("Hauptfenster immer im Vordergrund", isOn: $onTop)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
