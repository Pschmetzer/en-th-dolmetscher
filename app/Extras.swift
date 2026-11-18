// Extras.swift – kleine Bausteine rund um das Fenster: Rückmeldung für globale Kürzel (HUD), Aufwach-/Geräte-
// Ereignisse, URL-Schema (dolmetscher://), „Neu in dieser Version“, Untertitel-Fenster und Datei-Übersetzung.
import SwiftUI
import AppKit
import CoreAudio
import UniformTypeIdentifiers

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
        if let f = NSScreen.main?.visibleFrame {
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
            guard a.runModal() == .alertFirstButtonReturn else { return }
            UserDefaults.standard.set(true, forKey: Prefs.urlAllowed)
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

    static func items(for v: String = version) -> [String] {
        guard let url = Bundle.main.url(forResource: "whatsnew", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: [[String: String]]],
              let list = all[v] else { return [] }
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
            Text(L.f("whatsnew_title", WhatsNew.version)).font(.title2.bold())
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                Label { Text(t).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "sparkles").foregroundStyle(.tint)
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
    @AppStorage("partnerZoom") private var zoom = 1.0
    var body: some View {
        let last = m.items.last { !$0.pending && !$0.out.isEmpty }
        Text(last?.out ?? "")
            .font(.system(size: 28 * zoom, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
            .background(.ultraThinMaterial)
            .background(WindowAccessor { w in
                w.level = .floating
                w.isMovableByWindowBackground = true
                w.collectionBehavior.insert(.canJoinAllSpaces)
                w.sharingType = UserDefaults.standard.bool(forKey: Prefs.hideFromCapture) ? .none : .readOnly
            })
            .accessibilityLabel(last?.out ?? L.t("caption_title"))
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
