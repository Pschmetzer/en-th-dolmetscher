// HistoryView.swift – Runde 14: Verlauf-Fenster (gespeicherte Gespräche nach Tag und Sitzung, Suche, Filter,
// Umbenennen, Favoriten, Entfernen mit Rückgängig, Wiederöffnen im Hauptfenster nur lesend).
// Quelle ist allein `--history-export json` der Engine; Namen/Favoriten/Ausblenden bleiben lokal in der App.
import SwiftUI
import AppKit

/// Eine im Hauptfenster geöffnete gespeicherte Sitzung (nur lesen).
struct ViewedSession: Equatable {
    var title: String
    var items: [Utterance]
}

@MainActor
final class HistoryStore: ObservableObject {
    static let metaKey = "historyMeta"
    @Published var sessions: [HistorySession] = []
    @Published var meta: HistoryMeta = HistoryStore.loadMeta() {
        didSet { Self.saveMeta(meta) }
    }
    @Published var loading = false
    @Published var failed = false
    @Published var lastRemoved: String?
    private var undoTask: Task<Void, Never>?

    private static func loadMeta() -> HistoryMeta {
        guard let d = UserDefaults.standard.data(forKey: metaKey),
              let m = try? JSONDecoder().decode(HistoryMeta.self, from: d) else { return HistoryMeta() }
        return m
    }

    private static func saveMeta(_ m: HistoryMeta) {
        if let d = try? JSONEncoder().encode(m) { UserDefaults.standard.set(d, forKey: metaKey) }
    }

    /// Verlauf neu laden: Engine schreibt den JSON-Export in eine private Temp-Datei (0600), die App liest sie
    /// und löscht sie sofort wieder.
    func reload() {
        loading = true; failed = false
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dolm-history-" + UUID().uuidString)
        let file = dir.appendingPathComponent("h.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { loading = false; failed = true; return }
        var ok = false
        let started = EngineRunner.run(["--history-export", "json", "--out", file.path], timeout: 60, onEvent: { o in
            if o["exported"] as? Bool == true { ok = true }
        }, onExit: { [weak self] in
            var rows: [HistoryRow] = []
            if ok, let d = try? Data(contentsOf: file) { rows = HistoryLogic.parse(d) }
            try? FileManager.default.removeItem(at: dir)
            guard let self else { return }
            self.loading = false
            self.failed = !ok
            if ok {
                self.sessions = HistoryLogic.sessions(rows)
                self.meta = HistoryLogic.pruned(self.meta, keeping: Set(self.sessions.map { $0.id }))
            }
        })
        if started == nil { try? FileManager.default.removeItem(at: dir); loading = false; failed = true }
    }

    func rename(_ id: String, to name: String) { meta = HistoryLogic.renamed(meta, id: id, to: name) }
    func toggleFavorite(_ id: String) { meta = HistoryLogic.toggledFavorite(meta, id: id) }

    func remove(_ id: String) {
        meta = HistoryLogic.hiding(meta, id: id)
        lastRemoved = id
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if !Task.isCancelled { self?.lastRemoved = nil }
        }
    }

    func undoRemove() {
        guard let id = lastRemoved else { return }
        meta = HistoryLogic.restoring(meta, id: id)
        lastRemoved = nil
        undoTask?.cancel()
    }

    /// Anzeigename: eigener Name, sonst Uhrzeit.
    func title(_ s: HistorySession) -> String {
        let n = HistoryLogic.name(s, meta)
        return n.isEmpty ? s.start.formatted(date: .abbreviated, time: .shortened) : n
    }
}

extension Utterance {
    /// Gespeicherte Zeile als (nur lesbare) Blase. Richtung: Quellsprache laut Zeile, Ziel = die andere Seite
    /// des aktuellen Sprachpaars, sofern bekannt.
    init(history r: HistoryRow) {
        let to = r.lang == Langs.mine ? Langs.partner : Langs.mine
        self.init(uid: nil, translated: !r.translation.isEmpty, speaker: r.speaker, lang: r.lang, to: to,
                  text: r.text, out: r.translation, provider: r.provider,
                  textLatin: nil, outLatin: r.translit.isEmpty ? nil : r.translit)
        self.role = r.role
        self.date = r.time
        self.numWarn = HistoryLogic.hasNumberWarning(r)
    }
}

struct HistoryView: View {
    @EnvironmentObject var m: EngineModel
    @StateObject private var store = HistoryStore()
    @State private var filter = HistoryFilter()
    @State private var selection: String?
    @State private var confirmRemove: String?
    @State private var renaming: String?
    @State private var renameText = ""
    @FocusState private var searchFocused: Bool
    @AppStorage(L.key) private var uiLang = L.defaultCode

    private var result: (sessions: [HistorySession], hits: Int) {
        HistoryLogic.apply(store.sessions, filter: filter, meta: store.meta)
    }

    var body: some View {
        let _ = L.sync(uiLang)
        let res = result
        let days = HistoryLogic.days(res.sessions)
        VStack(spacing: 0) {
            controls(res.hits)
            Divider()
            HSplitView {
                list(days).frame(minWidth: 260, idealWidth: 320)
                detail(res.sessions).frame(minWidth: 320)
            }
            if store.lastRemoved != nil { undoBar }
        }
        .frame(minWidth: 760, minHeight: 460)
        .onAppear { store.reload() }
        .confirmationDialog(L.t("hist_remove_title"), isPresented: Binding(
            get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
            Button(L.t("hist_remove"), role: .destructive) {
                if let id = confirmRemove {
                    selection = HistoryLogic.neighbor(res.sessions.map { $0.id }, of: id)
                    store.remove(id)
                }
                confirmRemove = nil
            }
            Button(L.t("cancel"), role: .cancel) { confirmRemove = nil }
        } message: { Text(L.t("hist_remove_note")) }
        .sheet(isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) { renameSheet }
    }

    // MARK: Kopf: Suche, Filter, Trefferzahl

    private func controls(_ hits: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(L.t("hist_search"), text: $filter.query)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                .focused($searchFocused).accessibilityLabel(L.t("hist_search"))
                .onExitCommand { filter.query = ""; searchFocused = false }
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            filterMenu
            if filter.isActive {
                Text(L.f("hist_hits", hits)).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityLabel(L.f("hist_hits", hits))
                Button(L.t("reset_filter")) { filter = HistoryFilter() }
            }
            Spacer()
            if store.loading { ProgressView().controlSize(.small).accessibilityLabel(L.t("hist_loading")) }
            Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }
                .help(L.t("hist_reload")).accessibilityLabel(L.t("hist_reload"))
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var filterMenu: some View {
        Menu {
            Picker(L.t("hist_f_lang"), selection: $filter.lang) {
                Text(L.t("hist_f_all")).tag("")
                ForEach(HistoryLogic.languages(store.sessions), id: \.self) { c in
                    Text(Langs.flag(c) + " " + c.uppercased()).tag(c)
                }
            }
            Picker(L.t("hist_f_dir"), selection: $filter.role) {
                Text(L.t("hist_f_all")).tag("")
                Text(L.t("hist_f_me")).tag("me")
                Text(L.t("hist_f_other")).tag("other")
            }
            Divider()
            Toggle(L.t("hist_f_num"), isOn: $filter.numberWarning)
            Toggle(L.t("hist_f_weak"), isOn: $filter.weakTranslation)
            Toggle(L.t("hist_f_fav"), isOn: $filter.favoritesOnly)
        } label: {
            Label(L.t("hist_filter"), systemImage: filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .fixedSize().accessibilityLabel(L.t("hist_filter"))
    }

    // MARK: Liste nach Tag und Sitzung

    private func list(_ days: [HistoryDay]) -> some View {
        List(selection: $selection) {
            ForEach(days) { d in
                Section {
                    ForEach(d.sessions) { s in row(s).tag(s.id) }
                } header: {
                    Text(d.day.formatted(date: .complete, time: .omitted)).accessibilityAddTraits(.isHeader)
                }
            }
            if days.isEmpty { emptyNote }
        }
        .onDeleteCommand { if let id = selection { confirmRemove = id } }
        .onKeyPress(.return) { openSelected(); return selection == nil ? .ignored : .handled }
        .accessibilityLabel(L.t("hist_list"))
    }

    private var emptyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.failed ? L.t("hist_failed") : (filter.isActive || !store.sessions.isEmpty
                 ? L.t("no_results") : L.t("hist_empty"))).font(.headline)
            if !store.failed && store.sessions.isEmpty && !store.loading { Text(L.t("hist_empty_hint")).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 12).accessibilityElement(children: .combine)
    }

    private func row(_ s: HistorySession) -> some View {
        let fav = store.meta.favorites.contains(s.id)
        let name = HistoryLogic.name(s, store.meta)
        let time = s.start.formatted(date: .omitted, time: .shortened)
        let head = name.isEmpty ? time : name
        let sub = HistoryLogic.preview(s)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                if fav { Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityHidden(true) }
                Text(head).font(.headline).lineLimit(1)
                Spacer()
                Text(L.f("hist_count", s.rows.count)).font(.caption).foregroundStyle(.secondary)
            }
            if !name.isEmpty { Text(time).font(.caption).foregroundStyle(.secondary) }
            if !sub.isEmpty { Text(sub).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowLabel(head: head, time: time, count: s.rows.count, preview: sub, fav: fav))
        .contextMenu { actions(s.id) }
    }

    private func rowLabel(head: String, time: String, count: Int, preview: String, fav: Bool) -> String {
        var parts: [String] = []
        if fav { parts.append(L.t("hist_favorite")) }
        parts.append(head)
        if head != time { parts.append(time) }
        parts.append(L.f("hist_count", count))
        if !preview.isEmpty { parts.append(preview) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private func actions(_ id: String) -> some View {
        Button(L.t("hist_open")) { selection = id; openSelected() }
        Button(store.meta.favorites.contains(id) ? L.t("hist_unfavorite") : L.t("hist_favorite")) {
            store.toggleFavorite(id)
        }
        Button(L.t("hist_rename") + " …") { startRename(id) }
        Divider()
        Button(L.t("hist_remove") + " …", role: .destructive) { confirmRemove = id }
    }

    // MARK: Detail (nur lesen)

    @ViewBuilder private func detail(_ sessions: [HistorySession]) -> some View {
        if let id = selection, let s = sessions.first(where: { $0.id == id }) {
            VStack(spacing: 0) {
                HStack {
                    Text(store.title(s)).font(.title3.bold()).lineLimit(1).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { store.toggleFavorite(s.id) } label: {
                        Image(systemName: store.meta.favorites.contains(s.id) ? "star.fill" : "star")
                    }
                    .keyboardShortcut("d", modifiers: .command)
                    .help(L.t("hist_favorite"))
                    .accessibilityLabel(store.meta.favorites.contains(s.id) ? L.t("hist_unfavorite") : L.t("hist_favorite"))
                    Button { startRename(s.id) } label: { Image(systemName: "pencil") }
                        .help(L.t("hist_rename")).accessibilityLabel(L.t("hist_rename"))
                    Button(L.t("hist_open")) { openSelected() }
                        .buttonStyle(.borderedProminent)
                    Button(role: .destructive) { confirmRemove = s.id } label: { Image(systemName: "trash") }
                        .help(L.t("hist_remove")).accessibilityLabel(L.t("hist_remove"))
                }
                .padding(12)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(s.rows.enumerated()), id: \.offset) { _, r in line(r) }
                    }.padding(12)
                }
            }
        } else {
            Text(L.t("hist_pick")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func line(_ r: HistoryRow) -> some View {
        let time = r.time.formatted(date: .omitted, time: .standard)
        return VStack(alignment: .leading, spacing: 2) {
            Text(time + " · " + Langs.flag(r.lang) + " " + r.lang.uppercased()).font(.caption).foregroundStyle(.secondary)
            Text(r.text).textSelection(.enabled)
            if !r.translation.isEmpty { Text(r.translation).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(time + ", " + r.lang.uppercased() + ": " + r.text
                            + (r.translation.isEmpty ? "" : ". " + r.translation))
    }

    // MARK: Rückgängig, Umbenennen, Öffnen

    private var undoBar: some View {
        HStack {
            Image(systemName: "trash").accessibilityHidden(true)
            Text(L.t("hist_removed"))
            Spacer()
            Button(L.t("hist_undo")) { store.undoRemove() }.keyboardShortcut("z", modifiers: .command)
        }
        .padding(10).background(.bar)
        .accessibilityElement(children: .contain)
    }

    private func startRename(_ id: String) {
        renameText = store.meta.names[id] ?? ""
        renaming = id
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("hist_rename")).font(.headline).accessibilityAddTraits(.isHeader)
            TextField(L.t("hist_name_field"), text: $renameText)
                .textFieldStyle(.roundedBorder).frame(width: 280)
                .onSubmit { commitRename() }
            HStack {
                Spacer()
                Button(L.t("cancel")) { renaming = nil }.keyboardShortcut(.cancelAction)
                Button(L.t("save")) { commitRename() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func commitRename() {
        if let id = renaming { store.rename(id, to: renameText) }
        renaming = nil
    }

    /// Gewählte Sitzung nur lesend im Hauptfenster zeigen.
    private func openSelected() {
        guard let id = selection, let s = store.sessions.first(where: { $0.id == id }) else { return }
        m.viewingSession = ViewedSession(title: store.title(s), items: s.rows.map { Utterance(history: $0) })
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.title == L.t("app_title") { w.makeKeyAndOrderFront(nil) }
    }
}
