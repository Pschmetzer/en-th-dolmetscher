// SettingsR25.swift – Einstellungen der Runde 25: Ausgabe je Richtung (nur Einstellung, die Engine nutzt sie noch nicht)
// und Handoff des letzten Satzes. Regeln stehen in AudioRouteLogic und HandoffPayload (getestet in swift-tests).
import SwiftUI

/// Ausgabegerät je Richtung. Gespeichert wird die UID; ein nicht angeschlossenes Gerät bleibt sichtbar gewählt und wird gemeldet.
struct AudioRouteSection: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(AudioRouteLogic.mineKey) private var mine = ""
    @AppStorage(AudioRouteLogic.partnerKey) private var partner = ""
    @State private var outputs: [AudioOutputs.Device] = []

    private var route: AudioRoute { AudioRoute(mine: mine, partner: partner) }
    private var resolution: AudioRouteLogic.Resolution {
        AudioRouteLogic.resolve(route, fallback: m.outputDevice, available: outputs.map(\.uid))
    }

    private func picker(_ title: String, _ sel: Binding<String>) -> some View {
        Picker(title, selection: sel) {
            Text(R25T.t("route_default")).tag("")
            ForEach(outputs, id: \.uid) { Text($0.name).tag($0.uid) }
            if !sel.wrappedValue.isEmpty && !outputs.contains(where: { $0.uid == sel.wrappedValue }) {
                Text(sel.wrappedValue).tag(sel.wrappedValue)
            }
        }
        .accessibilityLabel(title)
    }

    var body: some View {
        Section {
            picker(R25T.t("route_mine"), $mine)
                .onAppear { outputs = AudioOutputs.list() }   // an der ersten Zeile, nicht an der Section
                .onReceive(NotificationCenter.default.publisher(for: .audioDevicesChanged)) { _ in outputs = AudioOutputs.list() }
            picker(R25T.t("route_partner"), $partner)
            if !resolution.missing.isEmpty {
                Label(R25T.t("route_missing"), systemImage: "exclamationmark.triangle").foregroundStyle(LangStyle.warning)
            }
            if AudioRouteLogic.sameDevice(route) {
                Label(R25T.t("route_same_warn"), systemImage: "info.circle").foregroundStyle(.secondary)
            }
            Text(R25T.t("route_note")).font(.caption).foregroundStyle(.secondary)
        } header: { Text(R25T.t("route_title")).accessibilityAddTraits(.isHeader) }
    }
}

/// Handoff des letzten Satzes (aus, solange der Nutzer es nicht einschaltet).
struct HandoffSection: View {
    @AppStorage(HandoffPayload.prefKey) private var on = false

    var body: some View {
        Section {
            Toggle(R25T.t("handoff_toggle"), isOn: $on).accessibilityLabel(R25T.t("handoff_toggle"))
            Text(R25T.t("handoff_note")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
