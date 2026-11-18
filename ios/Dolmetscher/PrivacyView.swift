// PrivacyView.swift – Datenschutz-Übersicht: was bleibt auf dem iPhone, was geht ins Netz (je nach Einstellung).
import SwiftUI

struct PrivacyView: View {
    @Environment(InterpreterModel.self) private var m
    @State private var whisper = WhisperStore.shared
    @ScaledMetric(relativeTo: .headline) private var iconWidth: CGFloat = 26

    var body: some View {
        List {
            Section {
                row("waveform", T("pv_speech"), T("pv_speech_d"), local: true)
                row(m.allowOnline ? "globe" : "iphone", T("pv_translate"),
                    T(m.allowOnline ? "pv_translate_on" : "pv_translate_off"), local: !m.allowOnline)
                if m.backCheck { row("arrow.uturn.backward", T("back_check"), T("pv_back_d"), local: true) }
                row("clock.arrow.circlepath", T("pv_history"), historyText, local: true)
                row("cross.case", T("em_card"), T("pv_card_d"), local: true)
            } header: { Text(T("pv_now")) }

            Section {
                row("arrow.down.circle", T("pv_models"), T(whisper.enabled ? "pv_models_whisper" : "pv_models_d"), local: false)
                row("person.crop.circle.badge.xmark", T("pv_none"), T("pv_none_d"), local: true)
            } footer: { Text(T("pv_footer")) }
        }
        .navigationTitle(T("privacy_overview"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var historyText: String {
        let keep: String
        switch m.historyDays {
        case 0: keep = T("history_none")
        case 1: keep = T("history_1d")
        case 7: keep = T("history_7d")
        case 30: keep = T("history_30d")
        default: keep = T("history_forever")
        }
        return String(format: T("pv_history_d"), keep) + " " + T(m.lockHistory ? "pv_lock_on" : "pv_lock_off")
    }

    private func row(_ icon: String, _ title: String, _ detail: String, local: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: iconWidth).foregroundStyle(local ? .green : .orange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(T(local ? "pv_local" : "pv_net"))
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background((local ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                        .foregroundStyle(local ? .green : .orange)
                }
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
