// R26Model.swift – Zustand der Runde 26: Gruppenmodus, Aufnahmequelle, Fähigkeiten der Engine, experimentelle Schalter,
// Latenz-Verteilung, `mic_gap`, Passwort des verschlüsselten Verlaufs. Hängt an EngineModel (`m.r26`), damit Engine.swift klein
// bleibt. Die Regeln selbst stehen in GroupSpeakerLogic / ExperimentalLogic (getestet in swift-tests).
import SwiftUI
import Security

/// Passwort des verschlüsselten Verlaufs im Schlüsselbund. Nie anzeigen, nie loggen; die Engine bekommt es per Umgebung
/// (Start, CLI-Aufrufe) und per Steuerfeld `history_password`. Kein Klartext-Rückfall in eine Datei.
enum HistoryPasswordStore {
    static let service = "Dolmetscher", account = "history-password"
    static let prefKey = "historyEncrypted"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    private nonisolated(unsafe) static var cached: String??

    static var enabled: Bool { UserDefaults.standard.bool(forKey: prefKey) }

    static var exists: Bool {
        var q = baseQuery
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func read() -> String? {
        if let c = cached { return c }
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        var v: String?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data {
            v = String(data: d, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
        }
        cached = .some(v)
        return v
    }

    @discardableResult
    static func save(_ pw: String) -> Bool {
        guard HistoryPasswordLogic.isValid(pw) else { return false }
        cached = nil
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = Data(pw.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "Dolmetscher – Verlauf"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess && read() == pw
    }

    static func remove() {
        cached = nil
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// Umgebung für Engine und CLI-Aufrufe: Passwort nur bei eingeschalteter Verschlüsselung.
    static func applyEnv(_ env: inout [String: String]) {
        HistoryPasswordLogic.apply(to: &env, enabled: enabled, password: enabled ? read() : nil)
    }
}

@MainActor
final class R26Model: ObservableObject {
    /// Wird von EngineModel gesetzt (sendet nur bei laufender Engine).
    var sender: (([String: Any]) -> Void)?
    private static var ud: UserDefaults { .standard }

    /// `ready.capabilities` der laufenden Engine; leer = unbekannt/ältere Engine.
    @Published private(set) var capabilities: [String] = []
    var knowsCapabilities: Bool { !capabilities.isEmpty }

    @Published var groupMode = ud.bool(forKey: "groupSpeakers") {
        didSet { Self.ud.set(groupMode, forKey: "groupSpeakers"); sender?(["group_speakers": groupMode]) }
    }
    /// "mic" | "system". Beim Start als `--source`, zur Laufzeit als Steuerfeld.
    @Published var source = AudioSourceLogic.normalize(ud.string(forKey: "audioSource")) {
        didSet {
            let n = AudioSourceLogic.normalize(source)
            if n != source { source = n; return }
            Self.ud.set(source, forKey: "audioSource")
            if source != oldValue { systemHint = false; sender?(["source": source]) }
        }
    }
    @Published private(set) var experimental: [String: Bool] =
        (ud.dictionary(forKey: "experimentalSwitches") as? [String: Bool]) ?? [:]
    @Published var historyEncrypted = HistoryPasswordStore.enabled {
        didSet {
            Self.ud.set(historyEncrypted, forKey: HistoryPasswordStore.prefKey)
            sendHistoryPassword()
        }
    }

    // Nur für die laufende Sitzung
    @Published private(set) var groupNames: [Int: String] = [:]
    @Published private(set) var groupSeen: [Int] = []
    @Published private(set) var latency: [LatencyHistLogic.Row] = []
    @Published private(set) var micGap = MicGapTracker()
    @Published private(set) var systemHint = false

    func supports(control id: String) -> Bool { ExperimentalLogic.supported(id, caps: capabilities) }
    func supports(feature name: String) -> Bool { ExperimentalLogic.feature(name, caps: capabilities) }

    // MARK: Engine-Ereignisse

    /// `ready`: Fähigkeiten merken und gespeicherte Wahl nachreichen (Engine startet immer mit den Standardwerten).
    func engineReady(_ o: [String: Any]) {
        capabilities = ExperimentalLogic.parseCaps(o["capabilities"])
        if groupMode && (supports(control: "group_speakers") || !knowsCapabilities) { sender?(["group_speakers": true]) }
        if source == AudioSourceLogic.system { systemHint = true }   // beim Start kommt `--source`; der Hinweis folgt als `hint`
        for (k, v) in ExperimentalLogic.controlsAfterReady(enabled: experimental, caps: capabilities) { sender?([k: v]) }
        sendHistoryPassword()
        sender?(["get_state": true])
    }

    func engineStopped() { capabilities = []; systemHint = false }

    func handleState(_ o: [String: Any]) {
        latency = LatencyHistLogic.parse(o["latency_hist"])
        let sw = ExperimentalLogic.parseSwitches(o["switches"])
        if !sw.isEmpty {   // Engine ist maßgeblich (z. B. nach Reconnect)
            var merged = experimental
            for (k, v) in sw { merged[k] = v }
            if merged != experimental { experimental = merged; Self.ud.set(merged, forKey: "experimentalSwitches") }
        }
    }

    func handleHint(_ o: [String: Any]) {
        switch o["code"] as? String {
        case "mic_gap": micGap.register()
        case "system_audio": systemHint = true
        default: break
        }
    }

    func refreshState() { sender?(["get_state": true]) }

    func resetSession() {
        groupNames = [:]; groupSeen = []; micGap.reset()
    }

    // MARK: Aktionen

    func setExperimental(_ id: String, _ on: Bool) {
        guard ExperimentalLogic.ids.contains(id) else { return }
        experimental[id] = on
        Self.ud.set(experimental, forKey: "experimentalSwitches")
        if supports(control: id) { sender?([id: on]) }
    }

    func noteGroup(_ n: Int) {
        if !groupSeen.contains(n) { groupSeen = GroupSpeakerLogic.numbers(from: groupSeen + [n]) }
    }

    /// Name setzen (nil/leer = zurück zur Nummer). Rückgabe: bereinigter Name.
    @discardableResult
    func setGroupName(_ n: Int, _ raw: String) -> String? {
        let clean = GroupSpeakerLogic.sanitize(raw)
        if let clean { groupNames[n] = clean } else { groupNames[n] = nil }
        return clean
    }

    func displayName(speaker: String?, group: Int) -> String? {
        GroupSpeakerLogic.displayName(speaker: speaker, group: group, renames: groupNames,
                                      defaultLabel: { R26T.f("grp_speaker", $0) })
    }

    /// Passwort an die Engine (vor `history`): gespeichertes Passwort bei eingeschalteter Verschlüsselung, sonst "" (löschen).
    func sendHistoryPassword() {
        let on = historyEncrypted
        guard on || supports(control: "history_password") else { return }   // ältere Engine: nichts senden, wenn aus
        sender?(["history_password": HistoryPasswordLogic.controlValue(enabled: on, password: on ? HistoryPasswordStore.read() : nil)])
    }
}

extension EngineModel {
    /// Sprecher umbenennen: gilt für schon gezeigte und künftige Blasen derselben Nummer.
    func renameGroupSpeaker(_ n: Int, to raw: String) {
        r26.setGroupName(n, raw)
        for i in items.indices where items[i].groupSpeaker == n {
            items[i].speaker = r26.displayName(speaker: GroupSpeakerLogic.engineLabel(n), group: n)
        }
    }
}
