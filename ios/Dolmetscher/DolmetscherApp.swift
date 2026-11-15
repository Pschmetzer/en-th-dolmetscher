// DolmetscherApp.swift – Einstieg der iPhone-App.
import SwiftUI

@main
struct DolmetscherApp: App {
    @State private var model = InterpreterModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .id(model.uiLang)   // Sprache der App gewechselt: Texte neu aufbauen
                .onChange(of: scenePhase) { _, phase in
                    // Im Hintergrund nicht weiter mithören.
                    if phase == .background { model.enteredBackground() }
                }
        }
    }
}
