// SettingsQuickPhrases.swift – Abschnitt „Schnellsätze“ der Einstellungen (aus SettingsView.swift herausgelöst, Runde 24).
// Die Regeln (Import-Zusammenführung, Kürzel-Grenze) stehen in QuickInputLogic.swift und sind in swift-tests geprüft.
import SwiftUI
import AppKit

struct QuickPhraseSettings: View {
    @AppStorage(Prefs.showQuick) private var showQuick = true
    @AppStorage(Prefs.quickPhrases) private var raw = Prefs.pairDefaults

    var body: some View {
        Section(L.t("quick_phrases")) {
            Toggle(L.t("show_quick"), isOn: $showQuick)
                .help(L.t("sh_show_quick"))
            Text(L.tp("quick_edit")).font(.callout).foregroundStyle(.secondary)
            let n = Prefs.phrases(raw).count
            if QuickPhraseLimit.overShortcutLimit(n) {
                Text(R24T.f("quick_over", n, QuickPhraseLimit.shortcutLimit))
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: $raw)
                .font(.body)
                .frame(minHeight: 140)
                .accessibilityLabel(L.tp("quick_edit"))
            HStack {
                Spacer()
                Button(L.t("quick_reset")) { raw = Prefs.pairDefaults }
                    .disabled(raw == Prefs.pairDefaults)
                Button(L.t("quick_import")) { importPhrases() }
                Button(L.t("quick_export")) { exportPhrases() }
                    .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

extension QuickPhraseSettings {
    fileprivate func importPhrases() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            raw = QuickPhraseImport.merge(existing: raw, imported: text)
        } catch { NSAlert(error: error).runModal() }
    }

    fileprivate func exportPhrases() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "quick-phrases.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data((raw + "\n").utf8).write(to: url, options: .atomic) }
        catch { NSAlert(error: error).runModal() }
    }
}
