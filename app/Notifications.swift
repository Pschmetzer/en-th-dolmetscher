// Notifications.swift – macOS-Mitteilung, wenn die Engine endgültig gestoppt ist und kein Fenster offen ist.
import AppKit
import UserNotifications

/// Nr. 351: Im Menüleisten-Betrieb (Fenster zu) merkte man einen Absturz nicht. Aktion „Neu starten“
/// (auch ein Klick auf die Mitteilung) ruft `onRestart`.
@MainActor
final class CrashNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CrashNotifier()
    static let category = "dolmetscher.crash"
    static let restartAction = "restart"
    var onRestart: (() -> Void)?
    private var installed = false

    /// Mitteilung nur ohne sichtbares Hauptfenster: sonst reicht der Absturz-Hinweis im Fenster.
    static func shouldNotify(mainWindowVisible: Bool, hasBundle: Bool) -> Bool { !mainWindowVisible && hasBundle }

    static var mainWindowVisible: Bool {
        NSApp.windows.contains { $0.identifier == Prefs.mainWindowID && $0.isVisible && !$0.isMiniaturized }
    }

    /// Delegate früh setzen (App-Start), damit auch ein Klick nach einem Neustart der App ankommt.
    func install() {
        guard !installed, Bundle.main.bundleIdentifier != nil else { return }
        installed = true
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        let restart = UNNotificationAction(identifier: Self.restartAction, title: L.t("restart"), options: [.foreground])
        c.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [restart],
                                                            intentIdentifiers: [], options: [])])
    }

    func notifyStopped(_ message: String) {
        guard Self.shouldNotify(mainWindowVisible: Self.mainWindowVisible,
                                hasBundle: Bundle.main.bundleIdentifier != nil) else { return }
        install()
        let title = L.t("crash_notify_title")
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            content.categoryIdentifier = CrashNotifier.category
            content.sound = .default
            c.add(UNNotificationRequest(identifier: "engine-stopped", content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let id = response.actionIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if id == CrashNotifier.restartAction || id == UNNotificationDefaultActionIdentifier {
                    NSApp.activate(ignoringOtherApps: true)
                    CrashNotifier.shared.onRestart?()
                }
            }
            done()
        }
    }
}
