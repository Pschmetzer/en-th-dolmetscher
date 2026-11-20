// PhrasebookView.swift – alle Szenario-Sätze durchsuchen und direkt sprechen.
import SwiftUI

struct PhrasebookView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(L.key) private var uiLang = L.defaultCode
    @State private var query = ""

    private var hits: [PhraseHit] {
        PhraseSearch.search(PresetCatalog.all.map { PhraseSource(id: $0.id, name: $0.name, phrases: $0.phrases) }, query: query)
    }

    var body: some View {
        let _ = L.sync(uiLang)
        let list = hits
        VStack(alignment: .leading, spacing: 8) {
            TextField(L.t("phrasebook_search"), text: $query).textFieldStyle(.roundedBorder)
                .accessibilityLabel(L.t("phrasebook_search"))
            if list.isEmpty {
                Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? L.t("phrasebook_hint") : L.t("phrasebook_none"))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(list) { h in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.en).fontWeight(h.critical ? .bold : .regular)
                            if !h.th.isEmpty { Text(h.th).foregroundStyle(.secondary) }
                            Text(h.presetName).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if !h.th.isEmpty {
                            Button("TH") { m.say(h.th, lang: "th") }
                                .help(L.t("phrasebook_speak")).accessibilityLabel(L.t("phrasebook_speak") + ": " + h.th)
                        }
                        Button("EN") { m.say(h.en, lang: "en") }
                            .help(L.t("phrasebook_speak")).accessibilityLabel(L.t("phrasebook_speak") + ": " + h.en)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 420, minHeight: 320)
    }
}
