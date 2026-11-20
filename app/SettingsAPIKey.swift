// SettingsAPIKey.swift – Abschnitt „API-Schlüssel“ des Einstellungsfensters (aus SettingsView.swift herausgelöst, Runde 25).
import SwiftUI

/// API-Schlüssel eingeben und im Schlüsselbund speichern (Rückfall: Datei 0600). Er wird nie angezeigt oder geloggt.
/// Ein „Schlüssel testen“-Knopf fehlt absichtlich: Er würde den Schlüssel lesen und an die API senden.
struct APIKeySection: View {
    @EnvironmentObject var m: EngineModel
    @State private var key = ""
    @State private var exists = APIKeyStore.exists
    @State private var failed = false
    @State private var formatWarn = false

    var body: some View {
        Section {
            SecureField(L.t("api_key"), text: $key)
                .onSubmit(save)
            HStack {
                if failed {
                    Label(L.t("key_failed"), systemImage: "xmark.octagon").foregroundStyle(.red)
                } else if exists && formatWarn {
                    Label(L.t("key_format_warn"), systemImage: "exclamationmark.triangle").foregroundStyle(LangStyle.warning)
                } else if exists {
                    Label(L.t("key_saved"), systemImage: "key.fill").foregroundStyle(LangStyle.success)
                } else {
                    Text(L.t("key_missing")).foregroundStyle(.secondary)
                }
                Spacer()
                if exists {
                    Button(L.t("key_remove"), role: .destructive) {
                        APIKeyStore.remove(); exists = APIKeyStore.exists; formatWarn = false; m.keyVersion += 1
                    }
                }
                Button(L.t("save"), action: save).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            RestartNote()
        } header: { Text(L.t("api_key")) }
    }

    private func save() {
        formatWarn = !APIKeyStore.looksValid(key)   // Nr. 390: trotzdem speichern, nur warnen
        let ok = APIKeyStore.save(key)
        key = ""                      // Eingabe sofort verwerfen
        failed = !ok
        exists = APIKeyStore.exists
        if ok { m.keyVersion += 1 }
    }
}
