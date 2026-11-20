// SettingsR26.swift – Einstellungen der Runde 26: Aufnahmequelle, Gruppenmodus, verschlüsselter Verlauf,
// Reiter „Experimentell“ (Schalter nach `ready.capabilities`), Latenz-Verteilung. Regeln: ExperimentalLogic (getestet).
import SwiftUI

/// Quelle (Mikrofon / Systemton) und Gruppenmodus. Beides wirkt sofort per Steuerfeld; ältere Engines melden es.
struct SourceAndGroupSection: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject var r: R26Model

    private var sourceUnsupported: Bool { r.knowsCapabilities && !r.supports(feature: "system_audio") }
    private var groupUnsupported: Bool { r.knowsCapabilities && !r.supports(control: "group_speakers") }

    var body: some View {
        Section {
            Picker(R26T.t("src_title"), selection: $r.source) {
                Text(R26T.t("src_mic")).tag(AudioSourceLogic.mic)
                Text(R26T.t("src_system")).tag(AudioSourceLogic.system)
            }
            .accessibilityLabel(R26T.t("src_title"))
            .disabled(sourceUnsupported)
            Text(sourceUnsupported ? R26T.t("src_unsupported") : R26T.t("src_note")).font(.caption).foregroundStyle(.secondary)
            if r.source == AudioSourceLogic.system && !sourceUnsupported {
                Label(R26T.t("hint_system_audio"), systemImage: "info.circle").foregroundStyle(LangStyle.warning)
            }
            Toggle(R26T.t("grp_toggle"), isOn: $r.groupMode)
                .accessibilityLabel(R26T.t("grp_toggle"))
                .disabled(groupUnsupported)
            Text(groupUnsupported ? R26T.t("grp_unsupported") : R26T.t("grp_note")).font(.caption).foregroundStyle(.secondary)
        } header: { Text(R26T.t("src_title")).accessibilityAddTraits(.isHeader) }
    }
}

/// Verlauf verschlüsseln: Passwort im Schlüsselbund, Weitergabe an die Engine (Umgebung + Steuerfeld).
struct HistoryPasswordSection: View {
    @ObservedObject var r: R26Model
    @State private var pw = ""
    @State private var exists = HistoryPasswordStore.exists
    @State private var invalid = false
    @State private var failed = false

    private var unsupported: Bool { r.knowsCapabilities && !r.supports(control: "history_password") }

    var body: some View {
        Section {
            Toggle(R26T.t("hpw_toggle"), isOn: $r.historyEncrypted)
                .accessibilityLabel(R26T.t("hpw_toggle"))
                .disabled(unsupported)
            SecureField(R26T.t("hpw_field"), text: $pw).onSubmit(save).accessibilityLabel(R26T.t("hpw_field"))
            HStack {
                if invalid { Label(R26T.t("hpw_invalid"), systemImage: "xmark.octagon").foregroundStyle(.red) }
                else if failed { Label(R26T.t("hpw_failed"), systemImage: "xmark.octagon").foregroundStyle(.red) }
                else if exists { Label(R26T.t("hpw_saved"), systemImage: "key.fill").foregroundStyle(LangStyle.success) }
                else { Text(R26T.t("hpw_missing")).foregroundStyle(.secondary) }
                Spacer()
                if exists {
                    Button(R26T.t("hpw_remove"), role: .destructive) {
                        HistoryPasswordStore.remove(); exists = false; r.historyEncrypted = false
                    }
                }
                Button(L.t("save"), action: save).disabled(pw.isEmpty)
            }
            if unsupported { Text(R26T.t("hpw_unsupported")).font(.caption).foregroundStyle(.secondary) }
            Text(R26T.t("hpw_note_plain")).font(.caption).foregroundStyle(.secondary)
            Text(R26T.t("hpw_note_lost")).font(.caption).foregroundStyle(.secondary)
            Text(R26T.t("hpw_clear_note")).font(.caption).foregroundStyle(.secondary)
        } header: { Text(R26T.t("hpw_title")).accessibilityAddTraits(.isHeader) }
    }

    private func save() {
        invalid = !HistoryPasswordLogic.isValid(pw)
        guard !invalid else { return }
        failed = !HistoryPasswordStore.save(pw)
        pw = ""                       // Eingabe sofort verwerfen
        exists = HistoryPasswordStore.exists
        if !failed { r.sendHistoryPassword() }
    }
}

/// Reiter „Experimentell“: sechs Schalter der Runde 24, nur wenn die Engine das Steuerfeld meldet.
struct ExperimentalSettings: View {
    @ObservedObject var r: R26Model

    var body: some View {
        Form {
            Section {
                Label(R26T.t("exp_warn"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(LangStyle.warning)
                if !r.knowsCapabilities { Text(R26T.t("exp_old_engine")).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                ForEach(ExperimentalLogic.ids, id: \.self) { id in
                    let ok = r.supports(control: id)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(R26T.t("exp_" + id), isOn: Binding(get: { r.experimental[id] ?? false },
                                                                   set: { r.setExperimental(id, $0) }))
                            .accessibilityLabel(R26T.t("exp_" + id))
                            .disabled(!ok)
                        Text(ok || !r.knowsCapabilities ? R26T.t("exp_" + id + "_note") : R26T.t("exp_not_supported"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text(R26T.t("exp_title")).accessibilityAddTraits(.isHeader) }
            LatencyHistSection(r: r)
        }
        .formStyle(.grouped)
        .onAppear { r.refreshState() }
    }
}

/// Latenz-Verteilung über Sitzungen aus `state.latency_hist` (Median und 95 %).
struct LatencyHistSection: View {
    @ObservedObject var r: R26Model

    private func title(_ k: String) -> String { R26T.t("lat_" + k) }

    var body: some View {
        Section {
            if r.latency.isEmpty {
                Text(R26T.t("lat_empty")).foregroundStyle(.secondary)
            } else {
                ForEach(r.latency, id: \.kind) { row in
                    let text = R26T.f("lat_row", row.n, LatencyHistLogic.seconds(row.p50), LatencyHistLogic.seconds(row.p95))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title(row.kind)).font(.callout)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.2))
                                Capsule().fill(Color.accentColor.opacity(0.35))
                                    .frame(width: g.size.width * LatencyHistLogic.fraction(row.p95, rows: r.latency))
                                Capsule().fill(Color.accentColor)
                                    .frame(width: g.size.width * LatencyHistLogic.fraction(row.p50, rows: r.latency))
                            }
                        }
                        .frame(height: 8)
                        .accessibilityHidden(true)
                        Text(text).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(title(row.kind) + ": " + text)
                }
            }
            Button(R26T.t("lat_refresh")) { r.refreshState() }
        } header: { Text(R26T.t("lat_title")).accessibilityAddTraits(.isHeader) }
    }
}
