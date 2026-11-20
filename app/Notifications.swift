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
        let summaryActions = NoticeLogic.actions(for: .summaryReady).map {
            UNNotificationAction(identifier: $0.id, title: R24T.t($0.labelKey), options: $0.foreground ? [.foreground] : [])
        }
        c.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [restart], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: SummaryNotifier.category, actions: summaryActions, intentIdentifiers: [], options: []),
        ])
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
        let cat = response.notification.request.content.categoryIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if cat == SummaryNotifier.category {
                    SummaryNotifier.handle(id)
                } else if id == CrashNotifier.restartAction || id == UNNotificationDefaultActionIdentifier {
                    NSApp.activate(ignoringOtherApps: true)
                    CrashNotifier.shared.onRestart?()
                }
            }
            done()
        }
    }
}

extension Notification.Name {
    static let openSummary = Notification.Name("DolmetscherOpenSummary")
    static let openCard = Notification.Name("DolmetscherOpenCard")
}

/// Nach einem längeren Gespräch (Mikrofon aus, App im Hintergrund): Mitteilung mit „Kopieren“ und „Öffnen“.
/// Die Zusammenfassung entsteht lokal (SummaryLogic); die Mitteilung enthält nur die Anzahl der Äußerungen.
@MainActor
enum SummaryNotifier {
    static let category = "dolmetscher.summary"
    static let minTurns = 5
    private static var lastDelivered: Date?
    private static var plainText = ""

    static func sessionEnded(_ m: EngineModel) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let items = m.items.filter { !$0.pending }.map(\.exportItem)
        guard items.count >= minTurns,
              NoticeLogic.shouldDeliver(appActive: NSApp.isActive, lastDelivered: lastDelivered, now: Date()) else { return }
        plainText = SummaryLogic.plain(SummaryLogic.summarize(items), labels: SummaryView.labels)
        lastDelivered = Date()
        CrashNotifier.shared.install()
        let n = items.count
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = R24T.t("n_summary_title")
            content.body = R24T.f("n_summary_body", n)
            content.categoryIdentifier = category
            c.add(UNNotificationRequest(identifier: "conversation-summary", content: content, trigger: nil))
        }
    }

    static func handle(_ action: String) {
        switch action {
        case "copy-summary": if !plainText.isEmpty { copyToPasteboard(plainText) }
        default: NSApp.activate(ignoringOtherApps: true); NotificationCenter.default.post(name: .openSummary, object: nil)
        }
    }
}
