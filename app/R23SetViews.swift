// R23SetViews.swift – Runde 23: Oberfläche zu R23SetLogic.swift (Einstellungen zurücksetzen/Vorschau, Statistik-Dashboard,
// Mikrofon-Test, Kopfhörer-Hinweis, Schlüssel-Test, Vorab-Prüfung, Restzeit, Sperrbildschirm, sensible Sitzung).
import AppKit
import AVFoundation
import Charts
import Combine
import CoreAudio
import Network
import SwiftUI

// MARK: - Einstellungen: Zurücksetzen je Reiter, Vorschau der Sicherungsdatei

struct SettingsResetRow: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject private var tracker = SettingsTracker.shared   // Aktualisierung, wenn sich Werte ändern
    let group: SettingGroup
    @State private var confirm = false

    var body: some View {
        let changed = R23Settings.changedKeys(group: group, current: SettingsStore.snapshot())
        let _ = tracker.log.count
        HStack {
            Button(R23T.t("reset_section")) { confirm = true }
                .disabled(changed.isEmpty)
                .help(R23T.t("reset_section_help"))
            if !changed.isEmpty {
                Text(R23T.f("reset_section_n", changed.count)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(R23T.t("reset_section_confirm"), isPresented: $confirm, titleVisibility: .visible) {
            Button(R23T.t("reset_section"), role: .destructive) {
                var imp = SettingsImport()
                imp.settings = R23Settings.resetValues(group: group, sensitiveActive: SensitiveSession.shared.active)
                m.applyImported(imp)
                Announcer.post(R23T.t("reset_section_done"))
            }
            Button(L.t("cancel"), role: .cancel) {}
        } message: { Text(R23T.t("reset_section_note")) }
    }
}

/// Zeigt vor dem Speichern, was in der Sicherungsdatei steht. Schlüssel und Gesprächsinhalte sind nie dabei.
struct SettingsExportPreviewSheet: View {
    @EnvironmentObject var m: EngineModel
    let onClose: () -> Void

    var body: some View {
        let lines = R23Settings.previewLines(values: SettingsStore.snapshot(), profile: SettingsStore.profile(glossary: m.glossary))
        VStack(alignment: .leading, spacing: 12) {
            Text(R23T.t("export_preview_title")).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            Label(R23T.t("export_preview_safe"), systemImage: "lock.shield").font(.callout)
            ScrollView {
                Text(lines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            .frame(height: 260).background(.quaternary.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(R23T.t("export_preview_title"))
            HStack { Spacer(); Button(L.t("ok"), action: onClose).keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 460)
    }
}

// MARK: - Verlauf: Statistik-Dashboard (Swift Charts)

struct R23StatsDashboard: View {
    let sessions: [HistorySession]
    let base: HistoryStatsResult        // Summen und häufige Sätze (HistoryLogic.stats)

    var body: some View {
        let st = R23StatsLogic.compute(sessions)
        let old = base
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L.t("hist_stats")).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Text(L.f("hist_stats_totals", old.utterances, old.sessions, old.words)).monospacedDigit()
                summary(st)
                chartBlock(R23T.t("stats_per_day")) {
                    Chart(st.perDay) { d in
                        BarMark(x: .value(R23T.t("stats_day"), String(d.label.suffix(5))), y: .value(R23T.t("stats_count"), d.count))
                    }
                }
                .accessibilityValue(st.perDay.map { "\($0.label): \($0.count)" }.joined(separator: ", "))
                chartBlock(R23T.t("stats_per_hour")) {
                    Chart(Array(st.perHour.enumerated()), id: \.offset) { h in
                        BarMark(x: .value(R23T.t("stats_hour"), h.offset), y: .value(R23T.t("stats_count"), h.element))
                    }
                    .chartXScale(domain: 0...23)
                }
                .accessibilityValue(st.perHour.enumerated().filter { $0.element > 0 }.map { "\($0.offset) h: \($0.element)" }.joined(separator: ", "))
                HStack(alignment: .top, spacing: 20) {
                    shareChart(R23T.t("stats_per_lang"), st.perLang.map { ($0.label == "?" ? "?" : Langs.flag($0.label) + " " + $0.label.uppercased(), $0.count) })
                    shareChart(R23T.t("stats_per_speaker"), st.perSpeaker.map { (Self.speakerName($0.label), $0.count) })
                }
                if !old.top.isEmpty {
                    Text(L.t("hist_stats_top")).font(.subheadline).foregroundStyle(.secondary)
                    ForEach(old.top, id: \.0) { t in
                        HStack { Text(t.0).lineLimit(1); Spacer(); Text("×\(t.1)").monospacedDigit() }
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 520, height: 560)
    }

    static func speakerName(_ k: String) -> String {
        k == "me" ? L.t("hist_f_me") : k == "other" ? L.t("hist_f_other") : k
    }

    private func summary(_ st: R23Stats) -> some View {
        HStack(spacing: 22) {
            stat(R23T.t("stats_conf"), st.avgConfidence.map { String(format: "%.0f %%", $0 * 100) } ?? "–")
            stat(R23T.t("stats_low"), "\(st.lowConfidence)")
            stat(R23T.t("stats_longest"), "\(st.longestSession)")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func chartBlock<C: View>(_ title: String, @ViewBuilder _ chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            chart().frame(height: 130)
        }
    }

    @ViewBuilder private func shareChart(_ title: String, _ data: [(String, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            if data.isEmpty {
                Text("–").foregroundStyle(.secondary)
            } else {
                Chart(Array(data.enumerated()), id: \.offset) { d in
                    SectorMark(angle: .value(R23T.t("stats_count"), d.element.1), innerRadius: .ratio(0.55))
                        .foregroundStyle(by: .value(title, d.element.0))
                }
                .frame(height: 130)
                .accessibilityValue(data.map { "\($0.0): \($0.1)" }.joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sensible Sitzung

/// „Sensible Sitzung“: nichts wird gespeichert (privater Modus, kein Verlauf, kein Textprotokoll) und danach ist alles
/// wie vorher. Zurücksetzen, Import oder Einstellungen können die Schalter während der Sitzung nicht lösen.
@MainActor
final class SensitiveSession: ObservableObject {
    static let shared = SensitiveSession()
    private static let key = "r23SensitiveSession"
    @Published private(set) var state: R23SensitiveState
    private var watchers: [AnyCancellable] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(R23SensitiveState.self, from: d) { state = s } else { state = R23SensitiveState() }
    }

    var active: Bool { state.active }

    private func flags(_ m: EngineModel) -> R23SensitiveFlags {
        R23SensitiveFlags(privateMode: m.privateMode, history: m.history, logText: m.logText)
    }

    private func apply(_ f: R23SensitiveFlags, _ m: EngineModel) {
        if m.history != f.history { m.history = f.history }
        if m.logText != f.logText { m.logText = f.logText }
        if m.privateMode != f.privateMode { m.privateMode = f.privateMode }
    }

    /// Beim Start: eine sensible Sitzung endet mit der App – den alten Zustand wiederherstellen.
    func recoverAtLaunch(_ m: EngineModel) {
        guard state.active else { return }
        toggle(m)
    }

    func toggle(_ m: EngineModel) {
        if state.active {
            watchers = []
            let r = R23Sensitive.leave(state)
            state = r.state
            if let f = r.restore { apply(f, m) }
        } else {
            let r = R23Sensitive.enter(state, current: flags(m))
            state = r.state
            apply(r.set, m)
            watch(m)
        }
        if let d = try? JSONEncoder().encode(state) { UserDefaults.standard.set(d, forKey: Self.key) }
        Announcer.post(R23T.t(state.active ? "sensitive_on" : "sensitive_off"), force: true)
    }

    /// Ändert jemand einen der Schalter, kommt er im nächsten Durchlauf zurück (@Published meldet vor dem Setzen).
    private func watch(_ m: EngineModel) {
        let check: () -> Void = { [weak self, weak m] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let m, let f = R23Sensitive.enforce(self.state, current: self.flags(m)) else { return }
                    self.apply(f, m)
                }
            }
        }
        watchers = [m.$privateMode.dropFirst().sink { _ in check() }, m.$history.dropFirst().sink { _ in check() },
                    m.$logText.dropFirst().sink { _ in check() }]
    }
}

// MARK: - Bildschirm gesperrt: Mikrofon pausieren

@MainActor
final class ScreenLockWatcher {
    static let shared = ScreenLockWatcher()
    static let prefKey = "pauseOnScreenLock"
    private var state = R23LockPause()
    private var started = false

    func start(_ m: EngineModel) {
        guard !started else { return }
        started = true
        let c = DistributedNotificationCenter.default()
        c.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let enabled = UserDefaults.standard.object(forKey: Self.prefKey) as? Bool ?? true
                if self.state.locked(active: m.active && m.running, paused: m.paused, enabled: enabled) { m.togglePause() }
            }
        }
        c.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if self.state.unlocked(paused: m.paused) { m.togglePause() }
            }
        }
    }
}

// MARK: - Einrichtung: Mikrofon-Test, Kopfhörer-Hinweis, Schlüssel testen

@MainActor
final class MicTester: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var level = 0.0
    @Published private(set) var verdict: MicVerdict?
    private var engine: AVAudioEngine?
    private var peak: Float = -120

    func start() {
        guard !running else { return }
        let e = AVAudioEngine()
        let input = e.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { verdict = .silent; return }
        peak = -120; verdict = nil
        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buf, _ in
            guard let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let db = R23Mic.db(rms: n > 0 ? (sum / Float(n)).squareRoot() : 0)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.tick(db) } }
        }
        do { try e.start() } catch { input.removeTap(onBus: 0); verdict = .silent; return }
        engine = e; running = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { MainActor.assumeIsolated { self.stop() } }
    }

    private func tick(_ db: Float) {
        guard running else { return }
        peak = max(peak, db)
        level = R23Mic.meter(db: db)
    }

    func stop() {
        guard running else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        running = false; level = 0
        verdict = R23Mic.verdict(peakDB: peak)
    }
}

struct MicTestRow: View {
    @ObservedObject var m: EngineModel
    @StateObject private var tester = MicTester()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(tester.running ? R23T.t("mictest_stop") : R23T.t("mictest_start")) {
                    tester.running ? tester.stop() : tester.start()
                }
                .disabled(m.active)
                if tester.running {
                    ProgressView(value: tester.level).frame(width: 140)
                        .accessibilityLabel(R23T.t("mictest_level"))
                        .accessibilityValue(String(format: "%.0f %%", tester.level * 100))
                }
            }
            if m.active { Text(R23T.t("mictest_busy")).font(.callout).foregroundStyle(.secondary) }
            if let v = tester.verdict {
                Text(R23T.t(Self.key(v))).font(.callout).foregroundStyle(v == .good ? Color.secondary : LangStyle.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !tester.running {
                Text(R23T.t("mictest_say")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    static func key(_ v: MicVerdict) -> String {
        switch v {
        case .silent: return "mictest_silent"
        case .tooQuiet: return "mictest_quiet"
        case .good: return "mictest_good"
        case .tooLoud: return "mictest_loud"
        }
    }
}

enum R23Audio {
    /// Name des Standard-Ausgabegeräts.
    static func defaultOutputName() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &s, &value) == noErr, let v = value?.takeRetainedValue() else { return nil }
        return v as String
    }
}

struct HeadphoneHintRow: View {
    @ObservedObject var m: EngineModel
    var body: some View {
        let name = R23Audio.defaultOutputName() ?? ""
        let kind = R23Headphones.classify(name)
        if R23Headphones.hintNeeded(output: kind, speakEnabled: m.speak) {
            Label(R23T.t("headphone_hint"), systemImage: "headphones")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
final class KeyTester: ObservableObject {
    enum State: Equatable { case idle, testing, badFormat(KeyFormat), done(KeyCheckResult) }
    @Published private(set) var state: State = .idle

    func run() {
        guard state != .testing else { return }
        guard let key = APIKeyStore.read() else { state = .badFormat(.empty); return }
        let f = R23Key.format(key)
        guard f == .ok else { state = .badFormat(f); return }
        state = .testing
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!, timeoutInterval: 12)
        req.setValue(R23Key.normalize(key), forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async { MainActor.assumeIsolated { self.state = .done(R23Key.result(status: code)) } }
        }.resume()
    }

    var messageKey: String? {
        switch state {
        case .idle: return nil
        case .testing: return "keytest_testing"
        case .badFormat(let f): return f == .empty ? "keytest_none" : "keytest_format"
        case .done(let r):
            switch r {
            case .valid: return "keytest_ok"
            case .rejected: return "keytest_rejected"
            case .rateLimited: return "keytest_ratelimit"
            case .serverError: return "keytest_server"
            case .offline: return "keytest_offline"
            case .unexpected: return "keytest_unexpected"
            }
        }
    }
}

struct KeyTestRow: View {
    @StateObject private var t = KeyTester()
    var body: some View {
        HStack {
            Button(R23T.t("keytest_button")) { t.run() }.disabled(t.state == .testing)
                .help(R23T.t("keytest_help"))
            if t.state == .testing { ProgressView().controlSize(.small).accessibilityLabel(R23T.t("keytest_testing")) }
            if let k = t.messageKey, t.state != .testing {
                Text(R23T.t(k)).font(.callout)
                    .foregroundStyle(k == "keytest_ok" ? LangStyle.success : LangStyle.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Erstinstallation: Vorab-Prüfung und Restzeit

@MainActor
final class NetProbe: ObservableObject {
    @Published private(set) var state: NetState = .unknown
    private var monitor: NWPathMonitor?

    init() {
        let mon = NWPathMonitor()
        mon.pathUpdateHandler = { [weak self] path in
            let s: NetState = path.status == .satisfied ? .online : .offline
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.state = s } }
        }
        mon.start(queue: DispatchQueue(label: "dolmetscher.netprobe"))
        monitor = mon
    }

    deinit { monitor?.cancel() }
}

struct PreflightNote: View {
    let needsDownload: Bool
    let requiredGB: Double
    @StateObject private var net = NetProbe()

    var body: some View {
        let issues = R23Preflight.evaluate(freeBytes: EnvSetupModel.freeBytes(), requiredGB: requiredGB, network: net.state,
                                           needsDownload: needsDownload)
        if issues.isEmpty {
            if needsDownload, net.state == .online {
                Label(R23T.t("preflight_ok"), systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(issues.enumerated()), id: \.offset) { _, i in
                    switch i {
                    case .noNetwork:
                        Label(R23T.t("preflight_net"), systemImage: "wifi.slash")
                    case .lowSpace(let need, let free):
                        Label(R23T.f("preflight_space", need, free), systemImage: "externaldrive.badge.exclamationmark")
                    }
                }
            }
            .font(.callout).foregroundStyle(LangStyle.warning).fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
final class ETATracker: ObservableObject {
    @Published private(set) var remaining: TimeInterval?
    private var eta = R23ETA()
    private var origin = Date()
    private var model = ""

    func update(_ d: EngineModel.Download?) {
        guard let d, let total = d.total, total > 0 else { eta = R23ETA(); remaining = nil; return }
        if d.model != model { model = d.model; eta = R23ETA(); origin = Date() }
        eta.add(done: Double(d.done), at: Date().timeIntervalSince(origin))
        remaining = eta.remaining(total: Double(total))
    }
}

struct ETALine: View {
    @ObservedObject var tracker: ETATracker
    var body: some View {
        if let r = tracker.remaining, r > 0 {
            Label(R23T.f("eta_line", R23ETA.format(r)), systemImage: "clock")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

// MARK: - Hilfe-Menü: Neuigkeiten, Problem melden, Einrichtung wiederholen

enum R23Help {
    @MainActor static func reportProblem() {
        let info = Bundle.main.infoDictionary ?? [:]
        let chip = HardwareInfo.sysctlString("machdep.cpu.brand_string")
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        if let u = R23Report.url(version: info["CFBundleShortVersionString"] as? String ?? "?",
                                 build: info["CFBundleVersion"] as? String ?? "?", macOS: os,
                                 chip: chip.isEmpty ? "?" : chip, uiLang: L.lang.rawValue) {
            NSWorkspace.shared.open(u)
        }
    }

    /// Einrichtung (Tipps mit Mikrofon, Sprachpaar, Modell, Schlüssel, Test) noch einmal zeigen.
    @MainActor static func restartOnboarding() {
        UserDefaults.standard.set(false, forKey: Prefs.tipsSeen)
        NotificationCenter.default.post(name: .showTips, object: nil)
    }
}

struct WhatsNewWindow: View {
    @AppStorage(L.key) private var uiLang = L.defaultCode
    var body: some View {
        let _ = L.sync(uiLang)
        let items = WhatsNew.items()
        VStack(alignment: .leading, spacing: 12) {
            Text(L.f("whatsnew_title", WhatsNew.version)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if items.isEmpty {
                Text(R23T.t("whatsnew_none")).foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                Label { Text(t).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "sparkles").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
            if let u = URL(string: "https://github.com/Pschmetzer/en-th-dolmetscher/blob/main/CHANGELOG.md") {
                Link(R23T.t("whatsnew_changelog"), destination: u)
            }
        }
        .padding(22).frame(width: 460, alignment: .leading)
    }
}

// MARK: - Tastenkürzel-Konflikte (Einstellungen)

struct HotKeyConflictList: View {
    @ObservedObject var hk: HotKeys
    var body: some View {
        let cfg = HotKeys.configured()
        let items = R23HotKeys.conflicts(failures: hk.failureDetails, configured: cfg, voiceOver: NSWorkspace.shared.isVoiceOverEnabled)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, c in
                    HStack(alignment: .firstTextBaseline) {
                        Label(text(c), systemImage: "exclamationmark.triangle.fill").foregroundStyle(LangStyle.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        if let s = c.suggestion, c.reason != .voiceOver {
                            Button(R23T.f("hk_use", HotKeyLogic.display(s))) { _ = hk.setLetter(s, for: c.actionID) }
                        }
                    }
                }
            }
        }
    }

    private func text(_ c: R23HotKeyConflict) -> String {
        let combo = HotKeyLogic.display(c.letter)
        switch c.reason {
        case .takenByOtherApp: return R23T.f("hk_taken_other", combo)
        case .invalid: return R23T.f("hk_invalid", combo)
        case .voiceOver: return R23T.t("hk_voiceover")
        case .unknown(let s): return R23T.f("hk_unknown", combo, Int(s))
        }
    }
}
