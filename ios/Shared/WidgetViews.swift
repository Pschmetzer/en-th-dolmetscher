// WidgetViews.swift – Ansichten des Schnellsätze-Widgets und der Live-Aktivität. Liegen in Shared, damit die App sie
// (nur DEBUG) für Screenshots zeigen kann; die Erweiterung bettet sie in Widget bzw. ActivityConfiguration ein.
import AppIntents
import SwiftUI
import WidgetKit

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

struct QuickPhrasesView: View {
    let entry: QuickPhrasesEntry
    let family: WidgetFamily

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

struct LiveStatusIcon: View {
    let status: ListeningActivityAttributes.Status
    private var tint: Color { status == .hearing ? .green : (status == .paused || status == .interrupted) ? .gray : .orange }
    var body: some View {
        Image(systemName: status.symbol).foregroundStyle(tint)
            .accessibilityHidden(true)
    }
}

struct StopButton: View {
    var body: some View {
        Button(intent: StopListeningIntent()) {
            Image(systemName: "stop.fill").foregroundStyle(.red)
        }
        .tint(.red)
        .accessibilityLabel(WidgetTexts.text("w_stop"))
    }
}

struct LastSentence: View {
    let state: ListeningActivityAttributes.ContentState
    var lines = 3
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        if redaction.contains(.privacy) || state.hidden == true {
            Text(WidgetTexts.text("w_hidden")).font(.subheadline).foregroundStyle(.secondary)
        } else if state.translation.isEmpty {
            Text(WidgetTexts.text("w_waiting")).font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.dstFlag) \(state.translation)").font(.headline).lineLimit(lines)
                Text("\(state.srcFlag) \(state.source)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Gesperrtes Gerät: das System verdeckt die Sätze (die App schickt dann ohnehin keine).
            .privacySensitive()
        }
    }
}

struct LiveLockView: View {
    let pair: String
    let state: ListeningActivityAttributes.ContentState
    /// Seit langer Zeit kein Update der App: der Stand kann veraltet sein (Fehlerfall, App beendet).
    var stale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LiveStatusIcon(status: state.status)
                Text(state.statusText).font(.subheadline.weight(.semibold))
                Spacer()
                Text(pair).font(.caption)
                StopButton()
            }
            LastSentence(state: state)
            if stale {
                Text(WidgetTexts.text("w_stale")).font(.caption).foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.white)
        // Große Schrift: Text darf wachsen, aber der Sperrbildschirm-Platz ist begrenzt.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
