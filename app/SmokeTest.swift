// SmokeTest.swift – Fenster-Selbsttest: baut jede Fenster-Ansicht der App einmal auf (ohne Fenster zu zeigen und ohne
// Engine-Aktionen) und prüft, dass Aufbau und Layout durchlaufen und eine Größe herauskommt. Aufruf: Hilfe-Menü
// „Fenster-Selbsttest“ oder `Dolmetscher --smoke-test` (Ausgabe auf stdout, Rückgabewert 0 = alles in Ordnung).
// Die Liste der Fenster steht in WindowCatalog (passt zu den Szenen in DolmetscherApp.swift).
import SwiftUI
import AppKit

@MainActor
enum SmokeTest {
    struct Result: Equatable { var id: String; var ok: Bool; var detail: String }

    static let launchArgument = "--smoke-test"

    /// Ansicht je Fenster-Kennung; nil = Kennung unbekannt (dann fehlt ein Eintrag hier).
    private static func view(_ id: String, _ model: EngineModel) -> AnyView? {
        switch id {
        case "main": return AnyView(ContentView().environmentObject(model))
        case "partner": return AnyView(PartnerView().environmentObject(model))
        case "history": return AnyView(HistoryView().environmentObject(model))
        case "whatsnew": return AnyView(WhatsNewWindow())
        case "mini": return AnyView(MiniView().environmentObject(model))
        case "phrasebook": return AnyView(PhrasebookView().environmentObject(model))
        case "numbers": return AnyView(NumbersView().environmentObject(model))
        case "summary": return AnyView(SummaryView().environmentObject(model))
        case "learn": return AnyView(LearnView().environmentObject(model))
        case "card": return AnyView(ShowCardView().environmentObject(model))
        case "shortcuts": return AnyView(ShortcutsWindowView())
        case "caption": return AnyView(CaptionView().environmentObject(model))
        default: return nil
        }
    }

    static func run(_ model: EngineModel) -> [Result] {
        WindowCatalog.ids.map { id in
            guard let v = view(id, model) else { return Result(id: id, ok: false, detail: "no view registered") }
            let host = NSHostingController(rootView: v)
            host.view.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
            host.view.layoutSubtreeIfNeeded()
            let size = host.view.fittingSize
            let ok = size.width > 0 && size.height > 0
            return Result(id: id, ok: ok, detail: ok ? "\(Int(size.width))x\(Int(size.height))" : "empty layout")
        }
    }

    static func summary(_ r: [Result]) -> String {
        let bad = r.filter { !$0.ok }.map { "\($0.id) (\($0.detail))" }
        var s = R25T.f("smoke_result", r.count - bad.count, r.count)
        if !bad.isEmpty { s += "\n" + R25T.f("smoke_failed", bad.joined(separator: ", ")) }
        return s
    }

    static func runAndShow(_ model: EngineModel) {
        let r = run(model)
        let a = NSAlert()
        a.messageText = R25T.t("smoke_menu")
        a.informativeText = summary(r)
        a.alertStyle = r.allSatisfy(\.ok) ? .informational : .warning
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Mit `--smoke-test` gestartet: einmal durchlaufen, Ergebnis ausgeben, beenden (Exit-Code 1 bei Fehlern).
    static func runIfRequested(_ model: EngineModel) {
        guard CommandLine.arguments.contains(launchArgument) else { return }
        let r = run(model)
        for x in r { print("\(x.ok ? "ok  " : "FAIL") \(x.id) \(x.detail)") }
        fflush(stdout)
        exit(r.allSatisfy(\.ok) ? 0 : 1)
    }
}
