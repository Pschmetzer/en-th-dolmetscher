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

struct PhraseItem: Hashable {
    var id: String
    var gloss: String
    var thai: String
}

struct QuickPhrasesEntry: TimelineEntry {
    var date = Date()
    var items: [PhraseItem]

    static let defaultIDs = ["Hello", "Thank you", "How much is this?", "Not spicy, please"]

    static func make(ids: [String], female: Bool) -> QuickPhrasesEntry {
        let list = (ids.isEmpty ? defaultIDs : ids).compactMap { id in PhraseData.all.first { $0.en == id } }
        let items = list.map {
            PhraseItem(id: $0.en, gloss: PhraseData.gloss($0, ui: WidgetTexts.lang), thai: PhraseData.fill($0.th, female: female))
        }
        return QuickPhrasesEntry(items: items)
    }
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
            QuickPhrasesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(WidgetTexts.text("w_phrases"))
        .description(WidgetTexts.text("w_phrases_d"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickPhrasesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickPhrasesEntry

    private var shown: [PhraseItem] { Array(entry.items.prefix(family == .systemSmall ? 2 : 4)) }
    private var columns: [GridItem] {
        family == .systemMedium ? [GridItem(.flexible()), GridItem(.flexible())] : [GridItem(.flexible())]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(shown, id: \.self) { p in PhraseButton(item: p) }
        }
    }
}

struct PhraseButton: View {
    let item: PhraseItem

    var body: some View {
        Button(intent: SayPhraseIntent(phraseID: item.id)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.thai).font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                Text(item.gloss).font(.caption2).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
