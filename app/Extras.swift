// Extras.swift – kleine Bausteine rund um das Fenster: Rückmeldung für globale Kürzel (HUD), Aufwach-/Geräte-
// Ereignisse, URL-Schema (dolmetscher://), „Neu in dieser Version“, Untertitel-Fenster und Datei-Übersetzung.
import SwiftUI
import AppKit
import CoreAudio
import UniformTypeIdentifiers
import Translation

extension Prefs {
    static let hideFromCapture = "hideFromCapture"       // Nr. 17: Fenster aus Bildschirmaufnahmen ausblenden
    static let stopMicOnClose = "stopMicOnClose"         // Nr. 18: Fenster schließen = Mikrofon aus
    static let hotkeyHUD = "hotkeyHUD"                   // Nr. 32: Rückmeldung für globale Kürzel
    static let urlAllowed = "urlSchemeAllowed"           // Nr. 53: Steuerung per dolmetscher:// erlaubt
    static let lastSeenVersion = "lastSeenVersion"       // Nr. 54
}

// MARK: Nr. 32 – kurze Einblendung für globale Kürzel

/// Kleines, nicht aktivierendes Panel (1 s). Nur wenn die App nicht vorn ist: sonst sieht man den Zustand ohnehin.
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var work: DispatchWorkItem?

    static func show(_ text: String) {
        guard UserDefaults.standard.object(forKey: Prefs.hotkeyHUD) as? Bool ?? true, !NSApp.isActive else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.alignment = .center
        label.setAccessibilityRole(.staticText)
        label.setAccessibilityLabel(text)
        label.sizeToFit()
        let size = NSSize(width: max(180, label.frame.width + 48), height: 56)
        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .hudWindow; fx.state = .active; fx.wantsLayer = true; fx.layer?.cornerRadius = 14
        label.frame = NSRect(x: 0, y: (size.height - label.frame.height) / 2, width: size.width, height: label.frame.height)
        fx.addSubview(label)
        let p = panel ?? NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .statusBar; p.ignoresMouseEvents = true
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = fx
        p.setContentSize(size)
        // Auf dem Bildschirm mit dem Mauszeiger (dort schaut der Nutzer hin), sonst Hauptbildschirm.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 60))
        }
        p.orderFrontRegardless()
        panel = p
        work?.cancel()
        let w = DispatchWorkItem { p.orderOut(nil) }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
        Announcer.post(text)
    }
}

// MARK: Nr. 21 / 27 – Aufwachen und Geräteliste

@MainActor
enum SystemEvents {
    private static var installed = false
    private static var listenerBlock: AudioObjectPropertyListenerBlock?

    static func install() {
        guard !installed else { return }
        installed = true
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    HotKeys.shared.retryIfNeeded()
                    EngineModel.shared.systemDidWake()
                }
            }
        }
        // Ein-/Ausstecken von Kopfhörern, AirPods, USB-Mikrofonen: Geräteliste neu laden lassen
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { NotificationCenter.default.post(name: .audioDevicesChanged, object: nil) }
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    }
}

extension Notification.Name {
    static let audioDevicesChanged = Notification.Name("DolmetscherAudioDevicesChanged")
}

// MARK: Nr. 53 – URL-Schema dolmetscher://start|stop|pause|say?text=…&lang=th

@MainActor
enum URLCommands {
    static func handle(_ url: URL) {
        guard url.scheme == "dolmetscher", let cmd = url.host?.lowercased() else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let m = EngineModel.shared
        // Erster Aufruf: nur nach Rückfrage (sonst könnte jede Webseite das Mikrofon starten)
        if !(UserDefaults.standard.object(forKey: Prefs.urlAllowed) as? Bool ?? false) {
            let a = NSAlert()
            a.messageText = L.t("url_allow_title")
            a.informativeText = L.t("url_allow_text")
            a.addButton(withTitle: L.t("url_allow"))
            a.addButton(withTitle: L.t("cancel"))
            // Nur dieser eine Aufruf: dauerhaft erlaubt wird ausschließlich im Einstellungs-Schalter,
            // sonst könnte danach jede Webseite ohne Rückfrage das Mikrofon starten.
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        switch cmd {
        case "start": if !m.active { m.startListening() }
        case "stop": if m.active { m.stopListening() }
        case "toggle": m.toggle()
        case "pause": if m.running && !m.paused { m.togglePause() }
        case "resume": if m.running && m.paused { m.togglePause() }
        case "say":
            guard let text = items.first(where: { $0.name == "text" })?.value?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= 1000 else { return }
            let lang = Langs.valid(items.first(where: { $0.name == "lang" })?.value) ?? Prefs.phraseLang(text)
            m.say(text, lang: lang)
        default: break
        }
    }
}

// MARK: Nr. 54 – „Neu in dieser Version“

/// `whatsnew.json` im Bundle: { "<Version>": [ {"de": "...", "en": "...", "th": "..."}, … ] }.
enum WhatsNew {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    /// whatsnew.json einmal laden (das Bundle ändert sich zur Laufzeit nicht).
    private static let table: [String: [[String: String]]]? = {
        guard let url = Bundle.main.url(forResource: "whatsnew", withExtension: "json"),
              let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: [[String: String]]]
    }()

    static func items(for v: String = version) -> [String] {
        guard let all = table, let list = all[v] else { return [] }
        return list.compactMap { $0[L.lang.rawValue] ?? $0["en"] }
    }

    /// Nach einem Update einmal zeigen; Erstinstallation (kein gespeicherter Stand) zeigt stattdessen die Tipps.
    @MainActor static func pending() -> [String] {
        let ud = UserDefaults.standard
        let seen = ud.string(forKey: Prefs.lastSeenVersion)
        guard !version.isEmpty, seen != version else { return [] }
        guard seen != nil else { ud.set(version, forKey: Prefs.lastSeenVersion); return [] }
        return items()
    }
    @MainActor static func markSeen() { UserDefaults.standard.set(version, forKey: Prefs.lastSeenVersion) }
}

struct WhatsNewSheet: View {
    let items: [String]
    let onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.f("whatsnew_title", WhatsNew.version)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                Label { Text(t).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "sparkles").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
            HStack { Spacer(); Button(L.t("ok"), action: onClose).keyboardShortcut(.defaultAction) }
        }
        .padding(22).frame(width: 440)
    }
}

// MARK: Nr. 52 – Untertitel-Fenster

/// Schmales Fenster mit der letzten Übersetzung (für Videoanrufe); Schriftgröße wie die Partner-Ansicht.
struct CaptionView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage("captionZoom") private var zoom = 1.0
    @AppStorage("captionOriginal") private var showOriginal = false
    @AppStorage("captionOpacity") private var opacity = 1.0
    @AppStorage("captionLines") private var lines = 1   // 1…3 letzte Übersetzungen (Rollen-Untertitel)
    var body: some View {
        let done = m.items.filter { !$0.pending && !$0.out.isEmpty }
        let last = done.last
        let earlier = Array(done.dropLast().suffix(max(0, min(3, lines) - 1)))
        VStack(spacing: 4) {
            ForEach(earlier) { u in
                Text(u.out).font(.system(size: 18 * zoom)).foregroundStyle(.secondary).lineLimit(2)
                    .minimumScaleFactor(0.5)
            }
            if last == nil {
                Text(L.t("chat_empty_start")).font(.system(size: 16 * zoom)).foregroundStyle(.secondary)
            }
            Text(last?.out ?? "")
                .font(.system(size: 28 * zoom, weight: .semibold))
                .minimumScaleFactor(0.4)
            if showOriginal, let o = last?.text {
                Text(o).font(.system(size: 15 * zoom)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .background(.ultraThinMaterial)
        .opacity(opacity)
        .contextMenu {   // Größe, Original und Durchsichtigkeit direkt am Untertitel-Fenster
            Button(L.t("font_bigger")) { zoom = min(2.5, zoom + 0.15) }
            Button(L.t("font_smaller")) { zoom = max(0.6, zoom - 0.15) }
            Toggle(L.t("caption_original"), isOn: $showOriginal)
            Picker(L.t("caption_lines"), selection: $lines) {
                ForEach([1, 2, 3], id: \.self) { Text("\($0)").tag($0) }
            }
            Picker(L.t("caption_opacity"), selection: $opacity) {
                ForEach([1.0, 0.85, 0.7, 0.5], id: \.self) { Text("\(Int($0 * 100)) %").tag($0) }
            }
            Divider()
            Button(L.t("copy_last")) { if let o = last?.out { copyToPasteboard(o) } }.disabled(last == nil)
        }
        .background(WindowAccessor { w in
            w.level = .floating
            w.isMovableByWindowBackground = true
            w.collectionBehavior.insert(.canJoinAllSpaces)
            w.sharingType = UserDefaults.standard.bool(forKey: Prefs.hideFromCapture) ? .none : .readOnly
            if w.frameAutosaveName.isEmpty { w.setFrameAutosaveName("DolmetscherCaptionWindow") }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(last.map { $0.out + (showOriginal ? ". " + $0.text : "") } ?? L.t("caption_title"))
    }
}

// MARK: Nr. 51 – Datei wählen

@MainActor
func chooseAudioFileToTranslate(_ m: EngineModel) {
    let p = NSOpenPanel()
    p.title = L.t("file_translate")
    p.allowedContentTypes = [.audio, .movie]
    p.allowsMultipleSelection = false
    if p.runModal() == .OK, let u = p.url { m.translateFile(u) }
}

// MARK: Nr. 25 / 26 – Offline-Übersetzung (Apple Translation) für das aktive Paar

/// Status des aktiven Sprachpaars laut `translate-helper --check --pairs …` (installed | supported | unsupported).
@MainActor
final class OfflinePairStatus: ObservableObject {
    static let shared = OfflinePairStatus()
    @Published private(set) var state: String?

    func refresh() {
        guard let helper = Paths.bundledTranslateHelper else { state = nil; return }
        let a = Langs.mine, b = Langs.partner
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: helper)
            p.arguments = ["--check", "--pairs", "\(a)-\(b),\(b)-\(a)"]
            let out = Pipe()
            p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
            var result: String?
            if (try? p.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first,
                   let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                   let pairs = o["pairs"] as? [String: String] {
                    let st = [pairs["\(a)-\(b)"], pairs["\(b)-\(a)"]].compactMap { $0 }
                    result = st.contains("unsupported") ? "unsupported" : st.contains("supported") ? "supported"
                        : st.isEmpty ? nil : "installed"
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { OfflinePairStatus.shared.state = result } }
        }
    }
}

/// Zeile unter dem Schalter „Offline-Übersetzung“: Status des Paars und (macOS 15+) Knopf für Apples Download-Dialog.
struct OfflinePackRow: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject private var st = OfflinePairStatus.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = st.state {
                Label(L.t("offline_pack_" + s), systemImage: s == "installed" ? "checkmark.circle" : s == "supported" ? "arrow.down.circle" : "xmark.circle")
                    .font(.caption).foregroundStyle(s == "installed" ? LangStyle.success : .secondary)
            }
            if st.state == "supported", #available(macOS 15.0, *) {
                OfflinePackButton { st.refresh() }
            }
        }
        .onAppear { st.refresh() }
        .onChange(of: m.mineLang) { st.refresh() }
        .onChange(of: m.partnerLang) { st.refresh() }
    }
}

@available(macOS 15.0, *)
struct OfflinePackButton: View {
    let onDone: () -> Void
    @State private var config: TranslationSession.Configuration?
    var body: some View {
        Button(L.t("offline_pack_download")) {
            if config != nil { config?.invalidate() } else {
                config = TranslationSession.Configuration(source: Locale.Language(identifier: Langs.mine),
                                                          target: Locale.Language(identifier: Langs.partner))
            }
        }
        .translationTask(config) { session in
            try? await session.prepareTranslation()      // zeigt Apples Download-Dialog
            await MainActor.run { onDone() }
        }
    }
}
