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

    /// Nr. 19: ⌘Q mitten im Gespräch (Mikrofon an, Übersetzung läuft, Ausgabe) erst nach Rückfrage.
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        let inUse = MainActor.assumeIsolated { () -> Bool in
            let m = EngineModel.shared
            return m.micOn || m.busy || m.speakingNow
        }
        guard inUse else { return .terminateNow }
        let a = NSAlert()
        a.messageText = L.t("quit_confirm_title")
        a.informativeText = L.t("quit_confirm_text")
        a.addButton(withTitle: L.t("quit"))
        a.addButton(withTitle: L.t("cancel"))
        let canExport = MainActor.assumeIsolated { !EngineModel.shared.items.isEmpty }
        if canExport { a.addButton(withTitle: L.t("export") + " …") }
        switch a.runModal() {
        case .alertFirstButtonReturn: return .terminateNow
        case .alertThirdButtonReturn:
            MainActor.assumeIsolated { exportConversation(EngineModel.shared) }
            DispatchQueue.main.async { NSApp.terminate(nil) }   // nach dem Export erneut fragen, ob beendet werden soll
            return .terminateCancel
        default: return .terminateCancel
        }
    }

    /// Nr. 53: dolmetscher://…
    func application(_ app: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { for u in urls { URLCommands.handle(u) } }
    }

    /// Dock-Menü: Start/Stopp, Pause und Fenster ohne das Fenster zu öffnen.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MainActor.assumeIsolated {
            let m = EngineModel.shared
            let menu = NSMenu()
            let toggle = NSMenuItem(title: m.active ? L.t("stop") : L.t("start"), action: #selector(dockToggle), keyEquivalent: "")
            toggle.target = self
            menu.addItem(toggle)
            let pause = NSMenuItem(title: m.paused ? L.t("resume") : L.t("pause"), action: #selector(dockPause), keyEquivalent: "")
            pause.target = self
            pause.isEnabled = m.running
            menu.addItem(pause)
            menu.addItem(.separator())
            let copy = NSMenuItem(title: L.t("copy_last"), action: #selector(dockCopy), keyEquivalent: "")
            copy.target = self
            copy.isEnabled = MenuBarLogic.canCopyLast(m.menuInput)
            menu.addItem(copy)
            let swap = NSMenuItem(title: L.t("menu_swap_pair"), action: #selector(dockSwap), keyEquivalent: "")
            swap.target = self
            menu.addItem(swap)
            return menu
        }
    }
    @objc private func dockToggle() { MainActor.assumeIsolated { EngineModel.shared.toggle() } }
    @objc private func dockCopy() { MainActor.assumeIsolated { EngineModel.shared.copyLastTranslation() } }
    @objc private func dockSwap() { MainActor.assumeIsolated { EngineModel.shared.swapPair() } }
    @objc private func dockPause() { MainActor.assumeIsolated { EngineModel.shared.togglePause() } }

    func applicationWillTerminate(_ n: Notification) {
        MainActor.assumeIsolated {
            HotKeys.shared.uninstall()
            EnvSetupModel.shared.terminateSetup()   // halbe Einrichtung abbrechen und aufräumen lassen
            EngineModel.shared.shutdown()
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.servicesProvider = TranslateService.shared   // Dienste-Menü: markierten Text übersetzen (NSServices in Info.plist)
        NSUpdateDynamicServices()
        signal(SIGPIPE, SIG_IGN)   // Schreiben in die Pipe einer beendeten Engine darf die App nicht beenden
        // Engine und globale Kürzel hängen an der App, nicht am Fenster (sie laufen auch bei geschlossenem Fenster).
        MainActor.assumeIsolated {
            HotKeys.shared.install(for: EngineModel.shared)
            EngineModel.shared.boot()   // Modelle im Hintergrund laden (Mikrofon aus)
            SystemEvents.install()      // Aufwachen (Nr. 21), Geräte ein-/ausgesteckt (Nr. 27)
        }
        // Nr. 18: Hauptfenster zu = Mikrofon aus (Einstellung, Standard an); sonst hört die App unbemerkt weiter
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, w.identifier == Prefs.mainWindowID,
                  UserDefaults.standard.object(forKey: Prefs.stopMicOnClose) as? Bool ?? true else { return }
            MainActor.assumeIsolated { if EngineModel.shared.active { EngineModel.shared.stopListening() } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { HotKeys.shared.retryIfNeeded() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // ⌘= (US-Tastatur ohne Umschalt) wirkt wie ⌘+ – ohne zweiten Menüeintrag.
            if mods == .command, e.charactersIgnoringModifiers == "=",
               e.window?.identifier == Prefs.mainWindowID {   // nur im Hauptfenster, nicht in Sheets/Einstellungen
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

extension EngineModel {
    /// Eingabe für MenuBarLogic (Symbol, Text, Aktionen).
    var menuInput: MenuBarInput {
        MenuBarInput(hasError: crashLog != nil || engineHung, loading: loadingModel, offline: !netDown.isEmpty,
                     active: active, paused: paused, speaking: !speakingIDs.isEmpty,
                     hasLast: lastReplayable != nil, running: running)
    }
    /// Sprachpaar tauschen (der didSet der Gegenseite vertauscht von selbst).
    func swapPair() {
        let s = MenuBarLogic.swapped(mine: mineLang, partner: partnerLang)
        mineLang = s.mine
        Announcer.post(Langs.label(s.mine) + " ⇄ " + Langs.label(s.partner))
    }
    func copyLastTranslation() {
        guard let u = lastReplayable else { return }
        copyToPasteboard(u.out)
        Announcer.post(L.t("copied"))
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: EngineModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false
    @AppStorage(L.key) private var uiLang = L.defaultCode   // Menüs neu aufbauen, wenn die Sprache wechselt
    @AppStorage(Prefs.quickPhrases) private var quickRaw = Prefs.pairDefaults

    /// Preset-Sätze wie in der Schnellsatz-Leiste (Nr. 35): (Text, Sprache) in der Reihenfolge „kritisch zuerst“.
    private var presetPhrases: [(String, String)] {
        guard let pr = PresetCatalog.all.first(where: { $0.id == model.preset }), model.activePreset != nil else { return [] }
        let fromEvent = model.activePreset?.id == pr.id
        let list = (fromEvent ? model.activePresetPhrases : nil) ?? pr.phrases
        let useTH = !Langs.hasEnglish && Langs.hasThai
        return (list.filter(\.critical) + list.filter { !$0.critical }).map { (useTH ? $0.th : $0.en, useTH ? "th" : "en") }
    }

    var body: some Commands {
        let _ = L.sync(uiLang)
        CommandMenu(L.t("quick_phrases")) {   // Nr. 35: ⌘1–⌘9 (eigene Sätze), ⌥⌘1–⌥⌘9 (Preset-Sätze)
            ForEach(Array(Prefs.phrases(quickRaw).prefix(9).enumerated()), id: \.offset) { i, p in
                Button(p) { model.say(p, lang: Prefs.phraseLang(p)) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .disabled(!model.engineReady)
            }
            let pp = presetPhrases
            if !pp.isEmpty { Divider() }
            ForEach(Array(pp.prefix(9).enumerated()), id: \.offset) { i, p in
                Button(p.0) { model.say(p.0, lang: p.1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
                    .disabled(!model.engineReady)
            }
        }
        CommandGroup(before: .saveItem) {   // Nr. 51
            Button(L.t("file_translate") + " …") { chooseAudioFileToTranslate(model) }
                .disabled(model.fileBusy)
        }
        CommandGroup(after: .undoRedo) {    // Nr. 34
            Button(L.t("undo_delete")) { model.undoDelete() }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(model.deletedBubble == nil)
        }
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
            Button(L.t("mini_title") + " (⌥⌘M)") { openWindow(id: "mini") }
                .keyboardShortcut("m", modifiers: [.option, .command])
            Button(L.t("caption_title")) { openWindow(id: "caption") }   // Nr. 52
            Button(L.t("phrasebook_title")) { openWindow(id: "phrasebook") }
            Button(L.t("hist_title")) { openWindow(id: "history") }
            Toggle(L.t("always_on_top"), isOn: $onTop)
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            // Nr. 376: Start/Stopp und Pause mit sichtbarem Kürzel im Menü
            Button(model.active ? L.t("stop") : L.t("start")) { model.toggle() }
                .keyboardShortcut(.return, modifiers: .command)
            Button(model.paused ? L.t("resume") : L.t("pause")) { model.togglePause() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!model.running)
            Button(L.t("copy_last")) { model.copyLastTranslation() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .accessibilityLabel(L.t("menu_copy_last_vo"))
                .disabled(model.lastReplayable == nil)
            Button(L.t("direction_cycle")) {
                let order = ["auto"] + Langs.pair
                let i = order.firstIndex(of: model.lang) ?? 0
                model.lang = order[(i + 1) % order.count]
            }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button(L.t("menu_swap_pair")) { model.swapPair() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .accessibilityLabel(L.t("menu_swap_vo"))
            Button(L.t("glossary_add_title") + " …") { NotificationCenter.default.post(name: .showGlossaryAdd, object: nil) }
                .keyboardShortcut("g", modifiers: [.command, .option])
            Button(L.t("focus_typing")) { NotificationCenter.default.post(name: .focusTyping, object: nil) }
                .keyboardShortcut("l", modifiers: .command)
            Button(L.t("speak_toggle")) { model.speak.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button(L.t("stop_speaking")) { model.stopSpeaking() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.running)
            // Nr. 375: letzte Übersetzung nochmal sprechen
            Button(L.t("replay_last")) { model.replayLast() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.lastReplayable == nil)
            Divider()
        }
        CommandGroup(replacing: .printItem) {}   // kein Drucken: ⌘P ist Pause
        CommandGroup(replacing: .help) {
            Button(L.t("tips_show")) { NotificationCenter.default.post(name: .showTips, object: nil) }
            Button(L.t("selftest_open")) { NotificationCenter.default.post(name: .showSelfTest, object: nil) }
            Button(L.t("show_shortcuts")) { NotificationCenter.default.post(name: .showShortcuts, object: nil) }
                .keyboardShortcut("/", modifiers: .command)
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
        let st = MenuBarLogic.status(m.menuInput)
        Text(L.f("menu_engine_status", L.t(MenuBarLogic.labelKey(st))))
        if !m.status.isEmpty { Text(m.status) }
        if let med = m.latencyMedian { Text("⏱ " + fmtSeconds(med)).help(L.t("latency_help")) }
        Divider()
        Button(m.active ? L.t("stop") : L.t("start")) { m.toggle() }
            .disabled(!MenuBarLogic.canToggle(st))
        Button(m.paused ? L.t("resume") : L.t("pause")) { m.togglePause() }
            .disabled(!MenuBarLogic.canPause(m.menuInput))
        Button(L.t("menu_swap_pair")) { m.swapPair() }
            .accessibilityLabel(L.t("menu_swap_vo"))
        Button(L.t("copy_last")) { m.copyLastTranslation() }
            .disabled(!MenuBarLogic.canCopyLast(m.menuInput))
            .accessibilityLabel(L.t("menu_copy_last_vo"))
        Button(L.t("stop_speaking")) { m.stopSpeaking() }
            .disabled(!m.running)
        RecentTranslationsMenu()
        Toggle(L.t("speak_toggle"), isOn: $m.speak)
        Picker(L.t("direction"), selection: $m.lang) {
            Text(L.t("dir_auto")).tag("auto")
            ForEach(Langs.pair, id: \.self) { c in Text(Langs.flag(c) + " " + L.f("dir_only", c.uppercased())).tag(c) }
        }
        Button(L.t("replay_last")) { m.replayLast() }
            .disabled(m.lastReplayable == nil)
        Button(L.t("translate_clipboard") + " (⌃⌥C)") { m.translateClipboard() }
            .disabled(!m.engineReady)
        if let d = m.download, let f = EnvLogic.downloadFraction(done: d.done, total: d.total) {
            Text(L.t("load_progress") + ": \(Int(f * 100)) %")
        }
        if m.mineLang == "th" || m.partnerLang == "th" {   // Nr. 374
            Picker(L.t("polite_label"), selection: $m.polite) {
                Text(L.t("polite_krub")).tag("krub")
                Text(L.t("polite_ka")).tag("ka")
            }
        }
        Divider()
        Button(L.t("show_window")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(L.t("glossary_add_title") + " …") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .showGlossaryAdd, object: nil)
        }
        Button(L.t("partner_view")) { openWindow(id: "partner"); NSApp.activate(ignoringOtherApps: true) }
        Button(L.t("mini_title")) { openWindow(id: "mini"); NSApp.activate(ignoringOtherApps: true) }
        Button(L.t("caption_title")) { openWindow(id: "caption"); NSApp.activate(ignoringOtherApps: true) }
        Button(L.t("phrasebook_title")) { openWindow(id: "phrasebook"); NSApp.activate(ignoringOtherApps: true) }
        Button(L.t("hist_title")) { openWindow(id: "history"); NSApp.activate(ignoringOtherApps: true) }
        Button(L.t("settings") + " …") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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

    init() {
        _ = L.lang              // Standardsprache festlegen, bevor die erste Ansicht @AppStorage liest
        APIKeyStore.migrate()   // alte Schlüsseldatei in den Schlüsselbund (Nr. 23), vor dem ersten Engine-Start
        SettingsTracker.shared.start()   // Runde 15: „Zuletzt geändert“ auch außerhalb des Einstellungsfensters
    }

    /// Nr. 360 / Runde 17: Fehler, Laden, Offline, Hören, Sprechen und Pause haben je eine eigene Form.
    private var menuIcon: String { MenuBarLogic.symbol(menuStatus) }

    /// Fehler (model.crashLog != nil), Laden (model.loadingModel) und Offline (model.netDown.isEmpty) vor dem Normalbetrieb.
    private var menuStatus: MenuBarStatus { MenuBarLogic.status(model.menuInput) }

    /// Zustand für VoiceOver: das Symbol ändert nur Form und Füllung.
    /// Offline heißt "menu_state_offline" (VoiceOver).
    private var menuState: String { L.t(MenuBarLogic.labelKey(menuStatus)) }

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

        Window(L.t("hist_title"), id: "history") {
            HistoryView().environmentObject(model)
        }
        .defaultSize(width: 900, height: 600)

        Window(L.t("mini_title"), id: "mini") {
            MiniView().environmentObject(model)
        }
        .defaultSize(width: 360, height: 150)
        .windowResizability(.contentMinSize)

        Window(L.t("phrasebook_title"), id: "phrasebook") {
            PhrasebookView().environmentObject(model)
        }
        .defaultSize(width: 480, height: 420)

        Window(L.t("caption_title"), id: "caption") {
            CaptionView().environmentObject(model)
        }
        .defaultSize(width: 760, height: 130)
        .windowStyle(.hiddenTitleBar)

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


/// Dienst „Mit Dolmetscher übersetzen“ (Rechtsklick → Dienste in jeder App): übersetzt und liest den markierten Text vor.
/// Der Text wird nur gesprochen, nicht ersetzt – der Dienst gibt nichts an die andere App zurück.
final class TranslateService: NSObject {
    static let shared = TranslateService()
    @objc func translateSelection(_ pboard: NSPasteboard, userData: String,
                                  error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let text = pboard.string(forType: .string)
        DispatchQueue.main.async { MainActor.assumeIsolated { EngineModel.shared.translateText(text) } }
    }
}
