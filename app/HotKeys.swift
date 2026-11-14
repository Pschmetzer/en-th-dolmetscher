// HotKeys.swift – globale Tastenkürzel über Carbon (RegisterEventHotKey), auch wenn die App im Hintergrund ist.
import Carbon
import AppKit

@MainActor
final class HotKeys: ObservableObject {
    static let shared = HotKeys()
    private var refs: [EventHotKeyRef] = []      // müssen am Leben bleiben, sonst ist das Kürzel weg
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]
    private weak var model: EngineModel?
    /// Kürzel, die nicht registriert werden konnten (z. B. schon vom System belegt), mit OSStatus.
    /// Die Einstellungen zeigen das an; bei App-Aktivierung folgt ein neuer Versuch.
    @Published private(set) var failures: [String] = []

    static let ctrlOpt = UInt32(controlKey | optionKey)

    private func register(id: UInt32, keyCode: Int, modifiers: UInt32, name: String, action: @escaping () -> Void) {
        installHandler()
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x444D_5448), id: id)   // 'DMTH'
        let st = RegisterEventHotKey(UInt32(keyCode), modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if st == noErr, let ref {
            refs.append(ref)
            actions[id] = action
        } else {
            failures.append("\(name) (OSStatus \(st))")
            NSLog("Dolmetscher: Tastenkürzel %@ nicht registriert, OSStatus %d", name, st)
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // C-Callback ohne Kontext: Weiterleitung über das statische `shared`.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard st == noErr else { return st }
            let id = hk.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeys.shared.fire(id) } }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func fire(_ id: UInt32) { actions[id]?() }

    /// Alle Kürzel sauber abmelden (sonst bleiben sie beim Neuregistrieren doppelt belegt).
    func uninstall() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
        actions.removeAll()
        if let h = handler { RemoveEventHandler(h); handler = nil }
    }

    /// ⌃⌥D = Start/Stopp (⌃⌥Leertaste ist in macOS der Eingabequellen-Wechsel), ⌃⌥P = Pause/Fortsetzen.
    /// Erneutes Aufrufen meldet erst ab und registriert dann neu.
    func install(for model: EngineModel) {
        self.model = model
        uninstall()
        failures = []
        register(id: 1, keyCode: kVK_ANSI_D, modifiers: Self.ctrlOpt, name: "⌃⌥D") { [weak model] in model?.toggle() }
        register(id: 2, keyCode: kVK_ANSI_P, modifiers: Self.ctrlOpt, name: "⌃⌥P") { [weak model] in model?.togglePause() }
    }

    /// Bei App-Aktivierung: nur nach einem Fehlschlag neu versuchen (z. B. wenn ein anderes Programm das Kürzel losließ).
    func retryIfNeeded() {
        guard !failures.isEmpty, let model else { return }
        install(for: model)
    }
}
