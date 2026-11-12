// Dolmetscher – SwiftUI-Oberfläche für die Python-Engine (dolmetscher.py).
// Weitere Dateien: Engine.swift (Prozess + Ereignisse), Views.swift (Hauptfenster), BubbleViews.swift (Sprechblasen),
// PartnerView.swift (Vollbild für die Partnerin), SettingsView.swift (⌘,), HotKeys.swift (globale Kürzel),
// Paths.swift (Python/ffmpeg/API-Schlüssel).
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: EngineModel?
    func applicationWillTerminate(_ n: Notification) { MainActor.assumeIsolated { model?.shutdown() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    private var keyMonitor: Any?
    func applicationDidFinishLaunching(_ n: Notification) {
        // ⌘= (US-Tastatur ohne Umschalt) wirkt wie ⌘+ – ohne zweiten Menüeintrag.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  e.charactersIgnoringModifiers == "=" else { return e }
            let ud = UserDefaults.standard
            let cur = ud.object(forKey: Prefs.fontScale) as? Double ?? 1.0
            ud.set(min(Prefs.fontRange.upperBound, ((cur + 0.1) * 10).rounded() / 10), forKey: Prefs.fontScale)
            return nil
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: EngineModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false

    private func zoom(_ d: Double) {
        scale = min(Prefs.fontRange.upperBound, max(Prefs.fontRange.lowerBound, (scale + d) * 10).rounded() / 10)
    }

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Gespräch exportieren …") { exportConversation(model) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.items.isEmpty)
        }
        CommandGroup(before: .toolbar) {
            Button("Schrift größer") { zoom(0.1) }.keyboardShortcut("+", modifiers: .command)
            Button("Schrift kleiner") { zoom(-0.1) }.keyboardShortcut("-", modifiers: .command)
            Button("Originalgröße") { scale = 1.0 }.keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Partner-Ansicht") { openWindow(id: "partner") }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Toggle("Immer im Vordergrund", isOn: $onTop)
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
            Button("Tipps anzeigen") { NotificationCenter.default.post(name: .showTips, object: nil) }
        }
    }
}

/// Menüleisten-Symbol: Start/Stopp, Pause, Vorlesen stoppen, Fenster zeigen.
struct MenuBarContent: View {
    @EnvironmentObject var m: EngineModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
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
    @StateObject var model = EngineModel()

    private var menuIcon: String {
        guard model.active else { return "waveform.circle" }
        return model.paused ? "pause.circle" : "waveform.circle.fill"
    }

    var body: some Scene {
        Window("Dolmetscher EN ⇄ TH", id: "main") {
            ContentView().environmentObject(model)
                .onAppear {
                    delegate.model = model
                    HotKeys.shared.install(for: model)
                    model.boot()   // Engine gleich im Hintergrund laden (Mikrofon aus)
                }
        }
        .commands { AppCommands(model: model) }

        Window("Partner-Ansicht", id: "partner") {
            PartnerView().environmentObject(model)
        }
        .defaultSize(width: 1000, height: 640)

        Settings {
            SettingsView().environmentObject(model)
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(model)
        } label: {
            Image(systemName: menuIcon).accessibilityLabel("Dolmetscher")
        }
    }
}
