// DolmetscherApp.swift – Einstieg der iPhone-App.
import CoreSpotlight
import SwiftUI

@main
struct DolmetscherApp: App {
    @State private var model = InterpreterModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                // 555: kein `.id(uiLang)` mehr – `T()` ist beobachtbar, Sheets und Entwürfe bleiben erhalten.
                .environment(\.locale, Locale(identifier: model.uiLang))
                .overlay {
                    // 567: Im App-Umschalter kein Gesprächsinhalt.
                    if ShieldPolicy.show(shield: model.privacyShield, active: scenePhase == .active,
                                         hideOnCapture: model.hideOnCapture, captured: model.screenCaptured) { PrivacyShield() }
                }
                .task { ExportCleanup.purge() }   // Reste früherer CSV-Exporte (Gesprächstext) im Temp-Ordner
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    model.openFavorite(key: activity.userInfo?[CSSearchableItemActivityIdentifier] as? String)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Im Hintergrund nicht weiter mithören.
                    if phase == .background { model.enteredBackground() }
                    if phase == .active { model.enteredForeground() }
                }
        }
    }
}
