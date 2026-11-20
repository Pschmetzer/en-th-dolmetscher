// HotKeys.swift – globale Tastenkürzel über Carbon (RegisterEventHotKey), auch wenn die App im Hintergrund ist.
import Carbon
import AppKit

@MainActor
final class HotKeys: ObservableObject {
    static let shared = HotKeys()
    private var refs: [EventHotKeyRef] = []      // müssen am Leben bleiben, sonst ist das Kürzel weg
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]
    /// Loslassen (nur Push-to-Talk braucht es).
    private var releaseActions: [UInt32: () -> Void] = [:]
    private weak var model: EngineModel?
    /// Kürzel, die nicht registriert werden konnten (z. B. schon vom System belegt), mit OSStatus.
    /// Die Einstellungen zeigen das an; bei App-Aktivierung folgt ein neuer Versuch.
    @Published private(set) var failures: [String] = []
    /// Runde 23: dieselben Fehlschläge mit Aktions-ID und OSStatus (R23HotKeys.conflicts schlägt freie Buchstaben vor).
    @Published private(set) var failureDetails: [(id: Int, status: Int32)] = []

    static let ctrlOpt = UInt32(controlKey | optionKey)

    private func register(id: UInt32, keyCode: Int, modifiers: UInt32, name: String,
                          onRelease: (() -> Void)? = nil, action: @escaping () -> Void) {
        installHandler()
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x444D_5448), id: id)   // 'DMTH'
        let st = RegisterEventHotKey(UInt32(keyCode), modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if st == noErr, let ref {
            refs.append(ref)
            actions[id] = action
            releaseActions[id] = onRelease
        } else {
            failures.append("\(name) (OSStatus \(st))")
            failureDetails.append((id: Int(id), status: st))
            NSLog("Dolmetscher: Tastenkürzel %@ nicht registriert, OSStatus %d", name, st)
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        // C-Callback ohne Kontext: Weiterleitung über das statische `shared`.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard st == noErr else { return st }
            let id = hk.id
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeys.shared.fire(id, released: released) } }
            return noErr
        }, specs.count, &specs, nil, &handler)
    }

    private func fire(_ id: UInt32, released: Bool) {
        if released { releaseActions[id]?() } else { actions[id]?() }
    }

    /// Alle Kürzel sauber abmelden (sonst bleiben sie beim Neuregistrieren doppelt belegt).
    func uninstall() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
        actions.removeAll()
        releaseActions.removeAll()
        if let h = handler { RemoveEventHandler(h); handler = nil }
    }

    /// ⌃⌥D = Start/Stopp (⌃⌥Leertaste ist in macOS der Eingabequellen-Wechsel), ⌃⌥P = Pause/Fortsetzen,
    /// ⌃⌥S = Vorlesen abbrechen, ⌃⌥R = letzte Übersetzung nochmal,
    /// ⌃⌥T halten = sprechen (nur im Push-to-Talk-Modus belegt, damit es anderen Programmen sonst nicht fehlt).
    /// Erneutes Aufrufen meldet erst ab und registriert dann neu.
    func install(for model: EngineModel) {
        self.model = model
        uninstall()
        failures = []
        failureDetails = []
        // Buchstaben je Aktion aus den Einstellungen (HotKeyLogic: eindeutig, Standard D/P/S/R/C/T).
        let keys = Self.configured()
        func reg(_ id: Int, onRelease: (() -> Void)? = nil, _ action: @escaping () -> Void) {
            guard let letter = keys[id], let code = HotKeyLogic.keyCode(letter) else { return }
            register(id: UInt32(id), keyCode: code, modifiers: Self.ctrlOpt, name: HotKeyLogic.display(letter),
                     onRelease: onRelease, action: action)
        }
        reg(1) { [weak model] in
            guard let model else { return }
            model.toggle()
            HUD.show(L.t(model.active ? "state_listening" : "stopped"))   // Nr. 32: tatsächlicher Zustand danach
        }
        reg(2) { [weak model] in
            guard let model else { return }
            guard model.running else { return }   // ohne laufende Engine tut das Kürzel nichts: kein falsches HUD
            model.togglePause()
            HUD.show(L.t(model.paused ? "state_paused" : "state_listening"))   // Nr. 32
        }
        // Nr. 379: im Gespräch am nötigsten, auch wenn die App im Hintergrund ist
        reg(4) { [weak model] in model?.stopSpeaking() }
        reg(6) { [weak model] in model?.translateClipboard() }
        reg(5) { [weak model] in model?.replayLast() }
        if model.pushToTalk {
            reg(3, onRelease: { [weak model] in model?.pttUp() }) { [weak model] in model?.pttDown() }
        }
    }

    /// Gewählte Buchstaben (UserDefaults, ungültige/doppelte Einträge fallen auf Standardwerte zurück).
    static func configured() -> [Int: Character] {
        HotKeyLogic.configured()
    }

    /// Buchstaben einer Aktion ändern und neu registrieren; false, wenn der Buchstabe schon vergeben/ungültig ist.
    @discardableResult
    func setLetter(_ letter: Character, for id: Int) -> Bool {
        guard let n = HotKeyLogic.assigned(letter, to: id, current: Self.configured()) else { return false }
        UserDefaults.standard.set(HotKeyLogic.serialized(n), forKey: HotKeyLogic.storageKey)
        objectWillChange.send()
        if let model { install(for: model) }
        return true
    }

    func resetLetters() {
        UserDefaults.standard.removeObject(forKey: HotKeyLogic.storageKey)
        objectWillChange.send()
        if let model { install(for: model) }
    }

    /// Bei App-Aktivierung: nur nach einem Fehlschlag neu versuchen (z. B. wenn ein anderes Programm das Kürzel losließ).
    func retryIfNeeded() {
        guard !failures.isEmpty, let model else { return }
        install(for: model)
    }
}
