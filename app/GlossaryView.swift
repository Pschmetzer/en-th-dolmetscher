// GlossaryView.swift – Glossar-Editor (Einstellungen): Suche, Warnungen, CSV, Vorschau, Rückgängig beim Löschen.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GlossaryEditorSheet: View {
    @EnvironmentObject var m: EngineModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var word = ""
    @State private var translation = ""
    @State private var sample = ""
    @State private var editing: Int? = nil          // Zeilenindex im Text
    @State private var deleted: (entry: GlossaryEntry, text: String)? = nil
    @State private var note = ""

    private var all: [GlossaryEntry] { GlossaryLogic.entries(m.glossary) }
    private var shown: [GlossaryEntry] { GlossaryLogic.filter(all, query: query) }
    private var issues: [Int: GlossaryIssueKind] {
        Dictionary(GlossaryLogic.issues(m.glossary).map { ($0.line, $0.kind) }, uniquingKeysWith: { a, _ in a })
    }

    static func issueText(_ k: GlossaryIssueKind) -> String {
        switch k {
        case .duplicate: return L.t("gl_issue_duplicate")
        case .conflict: return L.t("gl_issue_conflict")
        case .tooLong: return L.t("gl_issue_long")
        case .overLimit: return L.t("gl_issue_over")
        }
    }

    static func fatalText(_ code: String) -> String {
        switch code {
        case "size": return L.t("gl_import_fatal_size")
        case "encoding": return L.t("gl_import_fatal_encoding")
        case "rows": return L.t("gl_import_fatal_rows")
        default: return L.t("gl_import_fatal_binary")
        }
    }

    private func commit() {
        let t = GlossaryLogic.clean(word)
        guard !t.isEmpty else { return }
        if let i = editing {
            m.glossary = GlossaryLogic.replacing(line: i, term: word, translation: translation, in: m.glossary)
        } else {
            m.glossary = GlossaryLogic.appending(term: word, translation: translation, to: m.glossary)
        }
        m.flushGlossary()
        Announcer.post(L.f("glossary_learned", t))
        word = ""; translation = ""; editing = nil
    }

    private func delete(_ e: GlossaryEntry) {
        deleted = (e, m.glossary)
        m.glossary = GlossaryLogic.removing(line: e.line, from: m.glossary)
        m.flushGlossary()
        note = L.f("gl_deleted", e.term)
        Announcer.post(note)
    }

    private func undo() {
        guard let d = deleted else { return }
        m.glossary = d.text
        m.flushGlossary()
        deleted = nil
        note = L.t("gl_restored")
        Announcer.post(note)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Dolmetscher-glossary.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try GlossaryLogic.exportCSV(all).write(to: url, atomically: true, encoding: .utf8)
            note = L.f("gl_exported", all.count)
        } catch { note = L.t("export_failed") }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { note = L.t("sx_unreadable"); return }
        let r = GlossaryLogic.importCSV(data)
        if let f = r.fatal { note = Self.fatalText(f); return }
        let merged = GlossaryLogic.merge(r.entries, into: m.glossary)
        deleted = (GlossaryEntry(term: "", translation: "", line: -1), m.glossary)
        m.glossary = merged.text
        m.flushGlossary()
        note = L.f("gl_imported", merged.added, merged.duplicates + merged.conflicts, r.skipped.count + merged.rejected)
        Announcer.post(note)
    }

    private var hits: [GlossaryHit] { GlossaryLogic.preview(all, sample: sample) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("gl_title")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            HStack {
                TextField(L.t("gl_search"), text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L.t("gl_search"))
                Text(L.f("gl_count", all.count, GlossaryLogic.entryLimit)).foregroundStyle(.secondary)
            }
            entryList
            HStack {
                TextField(L.t("glossary_word"), text: $word).textFieldStyle(.roundedBorder).onSubmit(commit)
                    .accessibilityLabel(L.t("glossary_word"))
                TextField(L.t("glossary_translation"), text: $translation).textFieldStyle(.roundedBorder).onSubmit(commit)
                    .accessibilityLabel(L.t("glossary_translation"))
                Button(editing == nil ? L.t("add") : L.t("save"), action: commit)
                    .disabled(GlossaryLogic.clean(word).isEmpty)
                if editing != nil {
                    Button(L.t("cancel")) { editing = nil; word = ""; translation = "" }
                }
            }
            previewBox
            HStack {
                Button(L.t("gl_import")) { importCSV() }.help(L.t("gl_csv_help"))
                Button(L.t("gl_export")) { exportCSV() }.disabled(all.isEmpty)
                if deleted != nil { Button(L.t("undo_delete")) { undo() } }
                Text(note).foregroundStyle(.secondary).lineLimit(2).accessibilityLabel(note)
                Spacer()
                Button(L.t("close")) { m.flushGlossary(); dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 640, height: 560)
    }

    private var entryList: some View {
        List {
            if shown.isEmpty {
                Text(all.isEmpty ? L.t("gl_empty") : L.t("gl_no_match")).foregroundStyle(.secondary)
            }
            ForEach(shown, id: \.line) { e in
                row(e)
            }
        }
        .frame(minHeight: 180)
        .accessibilityLabel(L.t("glossary"))
    }

    private func row(_ e: GlossaryEntry) -> some View {
        let issue = issues[e.line]
        let shownText = e.translation.isEmpty ? L.t("gl_kept") : e.translation
        return HStack {
            VStack(alignment: .leading) {
                Text(e.term).bold()
                Text(shownText).font(.caption).foregroundStyle(.secondary)
                if let k = issue {
                    Label(Self.issueText(k), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(L.t("gl_edit")) { editing = e.line; word = e.term; translation = e.translation }
                .accessibilityLabel(L.f("gl_edit_named", e.term))
            Button(L.t("delete"), role: .destructive) { delete(e) }
                .accessibilityLabel(L.f("gl_delete_named", e.term))
        }
        .accessibilityElement(children: .contain)
    }

    private var previewBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(L.t("gl_sample"), text: $sample).textFieldStyle(.roundedBorder)
                .accessibilityLabel(L.t("gl_sample"))
            if !sample.isEmpty {
                if hits.isEmpty {
                    Text(L.t("gl_preview_none")).foregroundStyle(.secondary)
                } else {
                    ForEach(hits, id: \.term) { h in
                        Text(h.kept ? L.f("gl_preview_kept", h.term) : L.f("gl_preview_hit", h.term, h.result))
                    }
                }
            }
        }
    }
}
