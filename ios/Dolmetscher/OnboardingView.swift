// OnboardingView.swift – Willkommensfluss, Hinweisband bei verweigerter Berechtigung. Logik in Onboarding.swift.
import AVFoundation
import Speech
import SwiftUI
import Translation

/// Liest und erfragt die Systemfreigaben (nur hier, damit die Logik frameworkfrei bleibt).
enum PermissionProbe {
    static var microphone: PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .notDetermined
        }
    }

    static var speech: PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    static var summary: PermissionSummary { PermissionSummary(microphone: microphone, speech: speech) }

    static func requestMicrophone() async { _ = await AVAudioApplication.requestRecordPermission() }

    static func requestSpeech() async {
        _ = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
    }

    @MainActor static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

struct OnboardingView: View {
    @Environment(InterpreterModel.self) private var m
    @AppStorage("onboardingDone") private var done = false
    @AppStorage("onboardingLater") private var later = false
    @State private var flow = OnboardingFlow()
    @State private var perms = PermissionProbe.summary
    @State private var missingMB = 0
    @State private var checkedPacks = false
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(format: T("ob_step"), flow.step.position, OnboardingStep.count))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(T(flow.step.titleKey)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text(bodyText).fixedSize(horizontal: false, vertical: true)
                        stepContent
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                buttons.padding()
            }
            .navigationTitle(T("ob_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("ob_later")) { postpone() } }
            }
            .task { await refresh() }
            .translationTask(download) { session in
                try? await session.prepareTranslation()
                await m.refreshOffline()
                await refresh()
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: m.pair) { _, _ in Task { await refresh() } }
    }

    private var bodyText: String {
        if flow.step == .packs {
            guard let size = PackSize.format(mb: missingMB) else { return checkedPacks ? T("ob_packs_none") : "" }
            return String(format: T("ob_packs_b"), size)
        }
        return T(flow.step.bodyKey)
    }

    @ViewBuilder private var stepContent: some View {
        switch flow.step {
        case .pair:
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(T("lang_mine")) {
                    Picker(T("lang_mine"), selection: Binding(get: { m.pair.mine }, set: { m.pair = OnboardingFlow.pair(mine: $0, partner: m.pair.partner) })) {
                        ForEach(Lang.all) { l in Text("\(l.flag) \(l.english)").tag(l) }
                    }.labelsHidden()
                }
                LabeledContent(T("lang_partner")) {
                    Picker(T("lang_partner"), selection: Binding(get: { m.pair.partner }, set: { m.pair = OnboardingFlow.pair(mine: m.pair.mine, partner: $0) })) {
                        ForEach(Lang.all.filter { $0 != m.pair.mine }) { l in Text("\(l.flag) \(l.english)").tag(l) }
                    }.labelsHidden()
                }
            }
        case .microphone:
            permissionBlock(state: perms.microphone, deniedKey: "ob_mic_denied", restrictedKey: "ob_mic_restricted") {
                await PermissionProbe.requestMicrophone()
            }
        case .speech:
            permissionBlock(state: perms.speech, deniedKey: "ob_speech_denied", restrictedKey: "ob_speech_restricted") {
                await PermissionProbe.requestSpeech()
            }
        case .packs:
            if missingMB > 0 {
                Button { requestPacks() } label: { Label(T("ob_packs_load"), systemImage: "arrow.down.circle") }
                    .buttonStyle(.bordered)
            }
        case .test:
            Button { finish(testSentence: true) } label: { Label(T("ob_test_go"), systemImage: "text.bubble") }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private func permissionBlock(state: PermissionState, deniedKey: String, restrictedKey: String,
                                              request: @escaping () async -> Void) -> some View {
        switch PermissionAdvice.of(state) {
        case .explainThenAsk:
            Button(T("ob_allow")) { Task { await request(); perms = PermissionProbe.summary } }.buttonStyle(.borderedProminent)
        case .proceed:
            Label(T("ob_granted"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .openSettings, .restricted:
            VStack(alignment: .leading, spacing: 8) {
                Label(T(PermissionAdvice.of(state) == .restricted ? restrictedKey : deniedKey), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button(T("open_settings")) { PermissionProbe.openSettings() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var buttons: some View {
        HStack {
            if flow.step.previous != nil { Button(T("ob_back")) { flow.goBack() }.buttonStyle(.bordered) }
            Spacer()
            if flow.step.isLast {
                Button(T("ob_start")) { finish(testSentence: false) }.buttonStyle(.borderedProminent)
            } else {
                Button(T("ob_next")) { flow.advance() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func finish(testSentence: Bool) {
        done = true
        later = false
        m.sheet = nil
        if testSentence { m.submit(T("example_sentence")) }
    }

    private func postpone() {
        flow.later()
        later = true
        m.sheet = nil
    }

    private func requestPacks() {
        if download == nil {
            download = .init(source: Translator.language(m.pair.mine), target: Translator.language(m.pair.partner))
        } else {
            download?.invalidate()
        }
    }

    private func refresh() async {
        perms = PermissionProbe.summary
        let p = m.pair
        let rMine = await LangCheck.recognizer(p.mine), rPartner = await LangCheck.recognizer(p.partner)
        let tA = await LangCheck.translation(p.mine, p.partner), tB = await LangCheck.translation(p.partner, p.mine)
        let recognizers = [rMine, rPartner].filter { $0 == .downloadable }.count
        let translations = [tA, tB].filter { $0 == .downloadable }.count
        missingMB = PackSize.missingMB(recognizers: recognizers, translations: translations)
        checkedPacks = true
    }
}

/// Band im Gespräch, wenn eine Freigabe abgelehnt oder eingeschränkt ist: sagt es und führt in die Einstellungen.
struct PermissionBanner: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var summary = PermissionProbe.summary
    @State private var hidden = false

    var body: some View {
        Group {
            if let key = summary.bannerTextKey, !hidden {
                VStack(alignment: .leading, spacing: 8) {
                    Text(T(key)).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(T("open_settings")) { PermissionProbe.openSettings() }.buttonStyle(.borderedProminent)
                        Button(T("ob_later")) { hidden = true }.buttonStyle(.bordered)
                    }.controlSize(.small)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityElement(children: .contain)
            }
        }
        .onChange(of: scenePhase) { _, p in if p == .active { summary = PermissionProbe.summary; hidden = false } }
    }
}
