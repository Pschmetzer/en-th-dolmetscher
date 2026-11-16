// WidgetBundle.swift – Erweiterung: Schnellsätze-Widget, Steuerelement im Kontrollzentrum, Live-Aktivität.
import SwiftUI
import WidgetKit

@main
struct DolmetscherWidgets: WidgetBundle {
    var body: some Widget {
        QuickPhrasesWidget()
        StartControl()
        ListeningLiveActivity()
    }
}

/// Steuerelement „Dolmetscher starten“ (Kontrollzentrum, Sperrbildschirm, Aktionstaste).
struct StartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.dolmetscher.start") {
            ControlWidgetButton(action: StartInterpreterIntent()) {
                Label(WidgetTexts.text("w_start"), systemImage: "mic.fill")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_start")))
        .description(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_start_d")))
    }
}
