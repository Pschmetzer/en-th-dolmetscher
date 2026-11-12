// HotKeys.swift – globale Tastenkürzel über Carbon (RegisterEventHotKey), auch wenn die App im Hintergrund ist.
import Carbon
import Foundation

@MainActor
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [EventHotKeyRef] = []      // müssen am Leben bleiben, sonst ist das Kürzel weg
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]
    /// Kürzel, die nicht registriert werden konnten (z. B. schon vom System belegt), mit OSStatus.
    private(set) var failures: [String] = []

    static let ctrlOpt = UInt32(controlKey | optionKey)

    func register(id: UInt32, keyCode: Int, modifiers: UInt32, name: String, action: @escaping () -> Void) {
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

    /// ⌃⌥D = Start/Stopp (⌃⌥Leertaste ist in macOS der Eingabequellen-Wechsel), ⌃⌥P = Pause/Fortsetzen.
    func install(for model: EngineModel) {
        guard refs.isEmpty, failures.isEmpty else { return }
        register(id: 1, keyCode: kVK_ANSI_D, modifiers: Self.ctrlOpt, name: "⌃⌥D") { [weak model] in model?.toggle() }
        register(id: 2, keyCode: kVK_ANSI_P, modifiers: Self.ctrlOpt, name: "⌃⌥P") { [weak model] in model?.togglePause() }
    }
}
