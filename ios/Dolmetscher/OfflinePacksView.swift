// OfflinePacksView.swift – Runde 16: Übersicht „Offline-Sprachpakete“ (Einstellungen): Zustand je Baustein des aktuellen Paars,
// Laden, Größenhinweis, Reisewarnung, Satzbuch-Zusage und der Schalter „Nur offline“. Die Berechnung steht in OfflineReadiness.swift.
import Speech
import SwiftUI
import Translation

extension LangCheck {
    /// Sprachmodell der Erkennung über das System laden (einmalig, braucht Netz). Wirft, wenn es fehlschlägt.
    static func downloadRecognizer(_ l: Lang) async throws {
        guard let loc = await LangRecognizer.locale(for: l) else { throw SpeechError.unsupported(l) }
        let t = DictationTranscriber(locale: loc, contentHints: [], transcriptionOptions: [.punctuation],
                                     reportingOptions: [], attributeOptions: [])
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
    }
}

struct OfflinePacksView: View {
    @Environment(InterpreterModel.self) private var m
    @State private var inputs: OfflineInputs?
    @State private var loading: Set<PackKind> = []
    @State private var failed = false
    @State private var download: TranslationSession.Configuration?

    private var report: OfflineReport? {
        guard var i = inputs else { return nil }
        i.loading = loading
        return OfflineReport.evaluate(i)
    }

    private func name(_ l: Lang) -> String { "\(l.flag) \(l.name(in: m.uiLang))" }

    private func title(_ kind: PackKind) -> String {
        let p = m.pair
        switch kind {
        case .recognizer(let l): return String(format: T("off_recognizer"), name(l))
        case .voice(let l): return String(format: T("off_voice"), name(l))
        case .translation: return String(format: T("off_translation"), "\(p.mine.flag) ⇄ \(p.partner.flag)")
        }
    }

    var body: some View {
        @Bindable var m = m
        List {
            if let r = report { warningSection(r) }
            Section {
                if let r = report {
                    ForEach(r.items) { row($0) }
                } else {
                    ProgressView().accessibilityLabel(T("off_loading"))
                }
            } header: { Text("\(m.pair.mine.flag) ⇄ \(m.pair.partner.flag)") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("off_intro"))
                    if let r = report, r.items.contains(where: { if case .voice = $0.kind { return $0.state == .unavailable }; return false }) { Text(T("off_voice_hint")) }
                    if let r = report, r.phrasebookAlwaysOffline { Text(T("off_phrasebook")) }
                }
            }
            if let r = report, !r.loadable.isEmpty {
                Section {
                    Button { loadAll(r) } label: { Label(T("off_load_all"), systemImage: "arrow.down.circle") }
                        .disabled(r.isLoading)
                } footer: {
                    if let size = PackSize.format(mb: r.missingMB) { Text(String(format: T("off_size"), size)) }
                }
            }
            Section {
                Toggle(isOn: $m.offlineOnly) { Label(T("off_only"), systemImage: "airplane") }
            } footer: { Text(T("off_only_note")) }
        }
        .navigationTitle(T("off_title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task(id: m.pair) { await refresh() }
        .translationTask(download) { session in
            loading.insert(.translation)
            do { try await session.prepareTranslation() } catch { failed = true }
            loading.remove(.translation)
            await refresh()
            await m.refreshOffline()
        }
    }

    @ViewBuilder private func warningSection(_ r: OfflineReport) -> some View {
        Section {
            if let w = r.travelWarning {
                Label(String(format: T(w.textKey), warningList(w)), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(StatusColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(T("off_all_ok"), systemImage: "checkmark.seal.fill").foregroundStyle(StatusColor.ok)
            }
            if failed { Label(T("err_translate"), systemImage: "xmark.octagon.fill").foregroundStyle(StatusColor.error) }
        }
    }

    private func warningList(_ w: TravelWarning) -> String {
        switch w {
        case .missing(let k): return k.map(title).joined(separator: ", ")
        case .limited(let unavailable, _): return unavailable.map(title).joined(separator: ", ")
        }
    }

    private func row(_ item: PackItem) -> some View {
        let (label, icon, tint): (String, String, Color) = switch item.state {
        case .ready: (T("off_ready"), "checkmark.circle.fill", StatusColor.ok)
        case .missing: (T("off_missing"), "arrow.down.circle", StatusColor.warning)
        case .loading: (T("off_loading"), "arrow.triangle.2.circlepath", StatusColor.info)
        case .unavailable: (T("off_unavailable"), "xmark.circle.fill", StatusColor.error)
        }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(item.kind))
                Label(label, systemImage: icon).font(.footnote).foregroundStyle(tint)
                if item.state == .unavailable, !isVoice(item.kind) {
                    Text(T("off_unavail_hint")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.state == .loading { ProgressView().accessibilityHidden(true) }
            else if item.canLoadHere {
                Button(T("off_load")) { load(item.kind) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func isVoice(_ k: PackKind) -> Bool { if case .voice = k { return true }; return false }

    private func loadAll(_ r: OfflineReport) { for i in r.loadable where i.state == .missing { load(i.kind) } }

    private func load(_ kind: PackKind) {
        failed = false
        switch kind {
        case .translation:
            if download == nil {
                download = .init(source: Translator.language(m.pair.mine), target: Translator.language(m.pair.partner))
            } else { download?.invalidate() }
        case .recognizer(let l):
            loading.insert(kind)
            Task {
                do { try await LangCheck.downloadRecognizer(l) } catch { failed = true }
                loading.remove(kind)
                await refresh()
            }
        case .voice: break
        }
    }

    private func refresh() async {
        let p = m.pair
        let a = await LangCheck.translation(p.mine, p.partner), b = await LangCheck.translation(p.partner, p.mine)
        inputs = OfflineInputs(
            mine: p.mine, partner: p.partner,
            recognizerMine: await LangCheck.recognizer(p.mine), recognizerPartner: await LangCheck.recognizer(p.partner),
            translation: ReadinessReport.combine(a, b),
            voiceMine: Speaker.hasVoice(p.mine), voicePartner: Speaker.hasVoice(p.partner),
            phrasebook: p.features.thaiExtras)
    }
}
