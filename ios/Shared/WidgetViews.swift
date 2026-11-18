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
    /// So viele Sätze braucht die größte Ansicht höchstens.
    static let maxItems = 6
    /// Kategorie-Auswahl wechselt stündlich den Ausschnitt (Zeitleiste mit so vielen Einträgen).
    static let rotationSeconds: TimeInterval = 3600

    /// `ids`: vom Nutzer gewählte Sätze (nur eingebautes Satzbuch, nie Gesprächsinhalte). `category`: stattdessen eine
    /// ganze Kategorie des Satzbuchs, die über die Stunden rotiert. Ohne beides oder bei veralteten Kennungen gilt die
    /// feste Auswahl. Leere Liste = Satzbuch nicht lesbar (Fehlerzustand der Ansicht).
    static func make(ids: [String], category: String? = nil, female: Bool, date: Date = Date()) -> QuickPhrasesEntry {
        var list: [PhraseRecord]
        let pool = category.map { c in PhraseData.all.filter { $0.category == c } } ?? []
        if !pool.isEmpty {
            let start = Int(date.timeIntervalSince1970 / rotationSeconds) % pool.count
            list = (0..<min(maxItems, pool.count)).map { pool[(start + $0) % pool.count] }
        } else {
            list = ids.compactMap { id in PhraseData.all.first { $0.en == id } }
            if list.isEmpty { list = defaultIDs.compactMap { id in PhraseData.all.first { $0.en == id } } }
        }
        let items = list.map {
            PhraseItem(id: $0.en, gloss: PhraseData.gloss($0, ui: WidgetTexts.lang), thai: PhraseData.fill($0.th, female: female))
        }
        return QuickPhrasesEntry(date: date, items: items)
    }

    /// Zeitleiste: bei Kategorie ein Eintrag je Stunde für die nächsten Stunden, sonst genau einer.
    static func timeline(ids: [String], category: String?, female: Bool, now: Date = Date()) -> Timeline<QuickPhrasesEntry> {
        guard category != nil else {
            return Timeline(entries: [make(ids: ids, female: female, date: now)], policy: .never)
        }
        let hour = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / rotationSeconds).rounded(.down) * rotationSeconds)
        let entries = (0..<6).map { make(ids: ids, category: category, female: female, date: hour.addingTimeInterval(Double($0) * rotationSeconds)) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

/// Sprachpaar des Widgets (das eingebaute Satzbuch ist fest Englisch -> Thai).
enum WidgetPair {
    static let flags = "\u{1F1EC}\u{1F1E7} \u{2192} \u{1F1F9}\u{1F1ED}"
}

struct QuickPhrasesView: View {
    let entry: QuickPhrasesEntry
    let family: WidgetFamily
    @Environment(\.dynamicTypeSize) private var typeSize

    private var large: Bool { typeSize.isAccessibilitySize }
    private var count: Int {
        switch family {
        case .systemSmall: return large ? 1 : 2
        case .systemMedium: return large ? 2 : 4
        case .systemLarge: return large ? 3 : 6
        default: return 1
        }
    }
    private var shown: [PhraseItem] { Array(entry.items.prefix(count)) }
    private var columns: [GridItem] {
        family == .systemMedium && !large ? [GridItem(.flexible()), GridItem(.flexible())] : [GridItem(.flexible())]
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Button(intent: StartInterpreterIntent()) { Image(systemName: "mic.fill") }
                .accessibilityLabel(WidgetTexts.text("w_start"))
        case .accessoryInline:
            Text("\(WidgetPair.flags) \(entry.items.first?.thai ?? WidgetTexts.text("w_empty"))")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                PairHeader()
                if let first = entry.items.first { PhraseButton(item: first, compact: true) } else { EmptyNote() }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                PairHeader()
                if shown.isEmpty {
                    EmptyNote()
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(shown, id: \.self) { p in PhraseButton(item: p) }
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}

/// Sprachpaar sichtbar: Flaggen für das Auge, ausgeschriebener Text für VoiceOver.
struct PairHeader: View {
    var body: some View {
        Text(WidgetPair.flags).font(.caption2).foregroundStyle(.secondary)
            .accessibilityLabel(WidgetTexts.text("w_pair_a11y"))
    }
}

/// Fehlerzustand: das Satzbuch liess sich nicht lesen – nichts Verwirrendes anzeigen, sondern auf die App verweisen.
struct EmptyNote: View {
    var body: some View {
        Text(WidgetTexts.text("w_empty")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
    }
}

struct PhraseButton: View {
    let item: PhraseItem
    var compact = false

    var body: some View {
        Button(intent: SayPhraseIntent(phraseID: item.id)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.thai).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(compact ? Color.primary : StatusColor.warning)
                Text(item.gloss).font(.caption2).foregroundStyle(.secondary)
            }
            .lineLimit(compact ? 1 : 2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(compact ? 0 : 6)
        .background(compact ? Color.clear : StatusColor.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityHint(WidgetTexts.text("w_say_hint"))
    }
}

struct LiveStatusIcon: View {
    let status: ListeningActivityAttributes.Status
    private var tint: Color { status == .hearing ? StatusColor.ok : (status == .paused || status == .interrupted) ? Color.secondary : StatusColor.warning }
    var body: some View {
        Image(systemName: status.symbol).foregroundStyle(tint)
            .accessibilityHidden(true)
    }
}

struct StopButton: View {
    var body: some View {
        Button(intent: StopListeningIntent()) {
            Image(systemName: "stop.fill").foregroundStyle(StatusColor.error)
        }
        .tint(StatusColor.error)
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
                Text(WidgetTexts.text("w_stale")).font(.caption).foregroundStyle(StatusColor.warning)
            }
        }
        .foregroundStyle(.white)
        // Große Schrift: Text darf wachsen, aber der Sperrbildschirm-Platz ist begrenzt.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
