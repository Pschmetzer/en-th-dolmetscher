// Dolmetscher – SwiftUI-Oberfläche für die Python-Engine (dolmetscher.py).
// Weitere Dateien: Engine.swift (Prozess + Ereignisse), Views.swift (Hauptfenster), BubbleViews.swift (Sprechblasen),
// PartnerView.swift (Vollbild für die Partnerin), SettingsView.swift (⌘,), HotKeys.swift (globale Kürzel),
// Paths.swift (Python/ffmpeg/API-Schlüssel), Support.swift (Export, Diagnose, VoiceOver-Ansagen), L10n.swift (Texte).
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    /// Mit geschlossenem Fenster weiterlaufen, solange das Menüleisten-Symbol da ist (Einstellung).
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: Prefs.showMenuBar) as? Bool ?? true)
    }

    func applicationWillTerminate(_ n: Notification) {
        MainActor.assumeIsolated {
            HotKeys.shared.uninstall()
            EnvSetupModel.shared.terminateSetup()   // halbe Einrichtung abbrechen und aufräumen lassen
            EngineModel.shared.shutdown()
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        signal(SIGPIPE, SIG_IGN)   // Schreiben in die Pipe einer beendeten Engine darf die App nicht beenden
        // Engine und globale Kürzel hängen an der App, nicht am Fenster (sie laufen auch bei geschlossenem Fenster).
        MainActor.assumeIsolated {
            HotKeys.shared.install(for: EngineModel.shared)
            EngineModel.shared.boot()   // Modelle im Hintergrund laden (Mikrofon aus)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { HotKeys.shared.retryIfNeeded() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // ⌘= (US-Tastatur ohne Umschalt) wirkt wie ⌘+ – ohne zweiten Menüeintrag.
            if mods == .command, e.charactersIgnoringModifiers == "=" {
                let ud = UserDefaults.standard
                ud.set(Prefs.zoomed(ud.object(forKey: Prefs.fontScale) as? Double ?? 1.0, 0.1), forKey: Prefs.fontScale)
                return nil
            }
            // Leertaste = Start/Stopp, aber nur im Hauptfenster ohne Textfeld-Fokus (Suche, Glossar, Dialoge) und abschaltbar.
            if e.keyCode == 49, mods.isEmpty, !e.isARepeat,
               UserDefaults.standard.object(forKey: Prefs.spaceToggle) as? Bool ?? true,
               let w = NSApp.keyWindow, w.identifier == Prefs.mainWindowID,
               !(w.firstResponder is NSText), !(w.firstResponder is NSControl) {
                MainActor.assumeIsolated { EngineModel.shared.toggle() }
                return nil
            }
            return e
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: EngineModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false
    @AppStorage(L.key) private var uiLang = L.defaultCode   // Menüs neu aufbauen, wenn die Sprache wechselt

    var body: some Commands {
        let _ = L.sync(uiLang)
        CommandGroup(replacing: .saveItem) {
            Button(L.t("export") + " …") { exportConversation(model) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.items.isEmpty)
        }
        CommandGroup(after: .textEditing) {
            Button(L.t("find")) { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandGroup(before: .toolbar) {
            Button(L.t("font_bigger")) { scale = Prefs.zoomed(scale, 0.1) }.keyboardShortcut("+", modifiers: .command)
            Button(L.t("font_smaller")) { scale = Prefs.zoomed(scale, -0.1) }.keyboardShortcut("-", modifiers: .command)
            Button(L.t("font_reset")) { scale = 1.0 }.keyboardShortcut("0", modifiers: .command)
            Divider()
            Button(L.t("partner_view")) { openWindow(id: "partner") }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Toggle(L.t("always_on_top"), isOn: $onTop)
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button(model.paused ? L.t("resume") : L.t("pause")) { model.togglePause() }
                .disabled(!model.running)
            Button(L.t("stop_speaking")) { model.stopSpeaking() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.running)
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button(L.t("tips_show")) { NotificationCenter.default.post(name: .showTips, object: nil) }
        }
    }
}

/// Menüleisten-Symbol: Start/Stopp, Pause, Vorlesen stoppen, Fenster zeigen.
struct MenuBarContent: View {
    @EnvironmentObject var m: EngineModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(L.key) private var uiLang = L.defaultCode

    var body: some View {
        let _ = L.sync(uiLang)
        Text(m.status)
        Divider()
        Button(m.active ? L.t("stop") : L.t("start")) { m.toggle() }
        Button(m.paused ? L.t("resume") : L.t("pause")) { m.togglePause() }
            .disabled(!m.running)
        Button(L.t("stop_speaking")) { m.stopSpeaking() }
            .disabled(!m.running)
        Divider()
        Button(L.t("show_window")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button(L.t("quit")) { NSApp.terminate(nil) }
    }
}

@main
struct DolmetscherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = EngineModel.shared
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(L.key) private var uiLang = L.defaultCode

    init() { _ = L.lang }   // Standardsprache festlegen, bevor die erste Ansicht @AppStorage liest

    private var menuIcon: String {
        guard model.active else { return "waveform.circle" }
        return model.paused ? "pause.circle" : "waveform.circle.fill"
    }

    /// Zustand für VoiceOver: das Symbol ändert nur Form und Füllung.
    private var menuState: String {
        guard model.active else { return L.t("stopped") }
        return model.paused ? L.t("state_paused") : L.t("state_listening")
    }

    var body: some Scene {
        let _ = L.sync(uiLang)
        Window(L.t("app_title"), id: "main") {
            ContentView().environmentObject(model)
        }
        .commands { AppCommands(model: model) }

        Window(L.t("partner_title"), id: "partner") {
            PartnerView().environmentObject(model)
        }
        .defaultSize(width: 1000, height: 640)

        Settings {
            SettingsView().environmentObject(model)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarContent().environmentObject(model)
        } label: {
            Image(systemName: menuIcon)
                .accessibilityLabel("Dolmetscher")
                .accessibilityValue(menuState)
        }
    }
}
