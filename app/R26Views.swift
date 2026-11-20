// R26Views.swift – Ansichten der Runde 26: Sprecher-Farben und Umbenennen (Gruppenmodus), Hinweisbänder für `mic_gap`
// und den Systemton. Regeln in GroupSpeakerLogic / MicGapTracker (getestet in swift-tests).
import SwiftUI

enum GroupSpeakerStyle {
    /// Acht gut unterscheidbare Systemfarben; die Nummer steht immer zusätzlich im Namen (Farbe ist nie das einzige Merkmal).
    static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .brown, .indigo]
    static func color(_ n: Int) -> Color { palette[GroupSpeakerLogic.colorIndex(n)] }
}

/// Kleiner Farbpunkt vor dem Sprechernamen einer Blase (nur Gruppenmodus ohne Stimmprofil).
struct GroupSpeakerDot: View {
    let n: Int
    var body: some View {
        Circle().fill(GroupSpeakerStyle.color(n)).frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// Menü „Sprecher“ in der Gesprächsleiste: gesehene Nummern, Umbenennen per Dialog.
struct GroupSpeakerMenu: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject var r: R26Model
    @State private var renaming: Int?
    @State private var draft = ""

    var body: some View {
        if r.groupMode && !r.groupSeen.isEmpty {
            Menu {
                ForEach(r.groupSeen, id: \.self) { n in
                    Button { draft = r.groupNames[n] ?? ""; renaming = n } label: {
                        Label(R26T.t("grp_rename") + ": " + (r.displayName(speaker: nil, group: n) ?? ""),
                              systemImage: "circle.fill")
                            .foregroundStyle(GroupSpeakerStyle.color(n))
                    }
                }
            } label: {
                Label(R26T.t("grp_menu"), systemImage: "person.2.wave.2")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(R26T.t("grp_rename")).accessibilityLabel(R26T.t("grp_rename"))
            .alert(renaming.map { R26T.f("grp_rename_title", r.displayName(speaker: nil, group: $0) ?? "") } ?? "",
                   isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(R26T.t("grp_rename_field"), text: $draft)
                Button(L.t("save")) { if let n = renaming { m.renameGroupSpeaker(n, to: draft) }; renaming = nil }
                Button(L.t("cancel"), role: .cancel) { renaming = nil }
            } message: {
                Text(R26T.t("grp_rename_hint") + " " + R26T.t("grp_rename_note"))
            }
        }
    }
}

/// Hinweisbänder der Engine: Mikrofon-Lücke (`mic_gap`, 90 s sichtbar) und Systemton (`hint` `system_audio`).
struct R26Banners: View {
    @ObservedObject var r: R26Model
    @State private var systemClosed = false
    @State private var gapClosedAt: Date?

    var body: some View {
        Group {
            if r.systemHint && !systemClosed {
                NoticeBanner(icon: "speaker.wave.2.circle", tint: LangStyle.warning, text: R26T.t("hint_system_audio"),
                             onClose: { systemClosed = true })
            }
            // Läuft nach 90 s von selbst ab; TimelineView prüft ohne Timer-Verwaltung alle 10 s.
            TimelineView(.periodic(from: .now, by: 10)) { ctx in
                if r.micGap.visible(ctx.date), gapClosedAt.map({ $0 < (r.micGap.last ?? .distantPast) }) ?? true {
                    NoticeBanner(icon: "waveform.badge.exclamationmark", tint: LangStyle.warning,
                                 text: R26T.f("hint_mic_gap", r.micGap.count), onClose: { gapClosedAt = Date() })
                }
            }
        }
        .onChange(of: r.source) { _, _ in systemClosed = false }
    }
}
