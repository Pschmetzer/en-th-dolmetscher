// QuickPhrases.swift – Widget mit bis zu vier Satzbuch-Sätzen: Antippen öffnet die App, die den Satz vorliest.
// Die Auswahl kommt aus dem eingebauten Satzbuch (phrases.json liegt auch in der Erweiterung), eingestellt über
// App Intents – ohne App Group, daher keine eigenen Favoriten der App.
import AppIntents
import SwiftUI
import WidgetKit

struct PhraseEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Phrase"
    static let defaultQuery = PhraseQuery()

    var id: String
    var gloss: String
    var thai: String

    init(_ r: PhraseRecord) {
        id = r.en
        gloss = PhraseData.gloss(r, ui: WidgetTexts.lang)
        thai = PhraseData.fill(r.th, female: false)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(gloss)", subtitle: "\(thai)")
    }
}

struct PhraseQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PhraseEntity] {
        identifiers.compactMap { id in PhraseData.all.first { $0.en == id }.map(PhraseEntity.init) }
    }

    func entities(matching string: String) async throws -> [PhraseEntity] {
        PhraseData.all.filter {
            $0.en.localizedCaseInsensitiveContains(string) || ($0.de ?? "").localizedCaseInsensitiveContains(string) || $0.th.contains(string)
        }.map(PhraseEntity.init)
    }

    func suggestedEntities() async throws -> [PhraseEntity] { PhraseData.all.map(PhraseEntity.init) }
}

struct QuickPhrasesConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Quick phrases"

    @Parameter(title: "Phrases", size: 4)
    var phrases: [PhraseEntity]?

    @Parameter(title: "Female polite form (ค่ะ)", default: false)
    var female: Bool
}

struct QuickPhrasesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickPhrasesEntry { .make(ids: [], female: false) }

    func snapshot(for config: QuickPhrasesConfig, in context: Context) async -> QuickPhrasesEntry {
        .make(ids: config.phrases?.map(\.id) ?? [], female: config.female)
    }

    func timeline(for config: QuickPhrasesConfig, in context: Context) async -> Timeline<QuickPhrasesEntry> {
        Timeline(entries: [.make(ids: config.phrases?.map(\.id) ?? [], female: config.female)], policy: .never)
    }
}

struct QuickPhrasesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuickPhrases", intent: QuickPhrasesConfig.self, provider: QuickPhrasesProvider()) { entry in
            QuickPhrasesFamilyView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(WidgetTexts.text("w_phrases"))
        .description(WidgetTexts.text("w_phrases_d"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}


/// Liest die Widget-Größe aus der Umgebung (die geteilte Ansicht bekommt sie als Wert – so lässt sie sich
/// auch in der App für Screenshots zeigen).
struct QuickPhrasesFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickPhrasesEntry
    var body: some View { QuickPhrasesView(entry: entry, family: family) }
}
