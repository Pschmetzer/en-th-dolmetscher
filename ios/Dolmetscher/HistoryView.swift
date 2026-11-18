// HistoryView.swift – Runde 18: Verlauf als eigene Liste mit Suche, Filtern, Tagesgruppen, Mehrfachauswahl und Wischaktionen.
// Die Logik steht in HistoryLogic.swift (unit-getestet); hier nur Darstellung.
import SwiftUI

struct HistoryView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var filter = HistoryFilter()
    @State private var selecting = false
    @State private var selection = Set<UUID>()

    private var all: [Entry] { m.visibleEntries }
    private var shown: [Entry] { HistoryLogic.apply(filter, to: all, isFavorite: { m.isFavorite($0) }) }
    private var days: [HistoryDay] { HistoryLogic.groups(shown) }

    var body: some View {
        @Bindable var m = m
        return NavigationStack {
            content
                .navigationTitle(selecting ? String(format: T("hs_selected"), "\(selection.count)") : T("hs_title"))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $filter.query, prompt: T("hs_search"))
                .toolbar { topBar }
                .toolbar { if selecting { bottomBar } }
                .safeAreaInset(edge: .bottom) { undoBar }
        }
        .onChange(of: m.entries.count) { selection = selection.filter { id in m.entries.contains { $0.id == id } } }
    }

    // MARK: Inhalt

    @ViewBuilder private var content: some View {
        switch HistoryLogic.empty(total: all.count, shown: shown.count) {
        case .nothingSaved:
            ContentUnavailableView {
                Label(T("hs_empty_title"), systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text(T("hs_empty_hint"))
            } actions: {
                Button(T("hs_empty_go")) { dismiss() }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                retentionNote
            }
        case .noMatches:
            ContentUnavailableView {
                Label(T("hs_none_title"), systemImage: "magnifyingglass")
            } description: {
                Text(T("hs_none_hint"))
            } actions: {
                Button(T("hs_reset")) { filter = HistoryFilter() }.buttonStyle(.bordered).frame(minHeight: 44)
            }
        case .none:
            list
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(days) { d in
                Section(dayTitle(d.day)) {
                    ForEach(d.entries) { e in
                        row(e).tag(e.id)
                    }
                }
            }
            Section { retentionNote }
        }
        .environment(\.editMode, .constant(selecting ? .active : .inactive))
    }

    private func dayTitle(_ day: Date) -> String {
        switch HistoryLogic.label(for: day) {
        case .today: return T("hs_today")
        case .yesterday: return T("hs_yesterday")
        case .date(let d): return d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: m.uiLang)))
        }
    }

    private func row(_ e: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(LangStyle.flag(e.src)) → \(LangStyle.flag(e.target))")
                Text(e.date.formatted(date: .omitted, time: .shortened).description)
                Spacer(minLength: 0)
                if m.isFavorite(e) { Image(systemName: "star.fill").foregroundStyle(StatusColor.warning).accessibilityHidden(true) }
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(e.text).font(.subheadline).foregroundStyle(.secondary)
            if let t = e.translation { Text(t).font(.body.weight(.semibold)) }
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { m.delete(ids: [e.id]) } label: { Label(T("delete"), systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            if e.translation != nil {
                Button { m.toggleFavorite(e) } label: {
                    Label(m.isFavorite(e) ? T("unfavorite") : T("favorite"), systemImage: m.isFavorite(e) ? "star.slash" : "star")
                }
                .tint(StatusColor.warning)
            }
        }
    }

    private var retentionNote: some View {
        let note = HistoryLogic.retention(days: m.historyDays)
        let text = note.count.map { String(format: T(note.key), "\($0)") } ?? T(note.key)
        return VStack(spacing: 4) {
            Text(text).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(T("hs_keep_change")) { m.sheet = .settings }.font(.footnote).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var undoBar: some View {
        if m.canUndoClear {
            HStack {
                Text(m.notice ?? "").font(.subheadline).lineLimit(2)
                Spacer(minLength: 8)
                Button(T("undo")) { m.undoClear() }.buttonStyle(.borderedProminent).frame(minHeight: 44)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: Werkzeugleisten

    @ToolbarContentBuilder private var topBar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if selecting {
                Button(T("cancel")) { selecting = false; selection = [] }
            } else {
                Button(T("done")) { dismiss() }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if selecting {
                Button(T("hs_select_all")) { selection = HistoryLogic.toggleAll(visible: shown, selection: selection) }
            } else {
                filterMenu
                Button(T("hs_select")) { selecting = true }.disabled(shown.isEmpty)
            }
        }
    }

    @ToolbarContentBuilder private var bottomBar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            ShareLink(item: TranscriptExport(entries: HistoryLogic.selected(all, ids: selection), lang: m.uiLang),
                      preview: SharePreview(T("hs_share_sel"))) {
                Label(T("hs_share_sel"), systemImage: "square.and.arrow.up")
            }
            .disabled(selection.isEmpty)
            Spacer()
            Button(role: .destructive) {
                m.delete(ids: selection)
                selection = []
                selecting = false
            } label: { Label(T("hs_delete_sel"), systemImage: "trash") }
                .disabled(selection.isEmpty)
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker(T("hs_filter"), selection: $filter.range) {
                ForEach(HistoryRange.allCases, id: \.self) { Text(T($0.textKey)).tag($0) }
            }
            Picker(T("hs_all_pairs"), selection: $filter.pair) {
                Text(T("hs_all_pairs")).tag(HistoryPair?.none)
                ForEach(HistoryLogic.pairs(in: all), id: \.self) { p in
                    Text("\(p.first.flag) \(p.first.native) ↔ \(p.second.flag) \(p.second.native)").tag(Optional(p))
                }
            }
            Toggle(T("hs_favs"), isOn: $filter.favoritesOnly)
            if filter.isActive { Button(T("hs_reset")) { filter = HistoryFilter() } }
        } label: {
            Image(systemName: filter.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .minTapTarget()
        }
        .accessibilityLabel(T("hs_filter"))
    }
}
