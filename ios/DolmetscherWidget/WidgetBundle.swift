// WidgetBundle.swift – Erweiterung: Schnellsätze-Widget, Steuerelement im Kontrollzentrum, Live-Aktivität.
import SwiftUI
import WidgetKit

@main
struct DolmetscherWidgets: WidgetBundle {
    var body: some Widget {
        QuickPhrasesWidget()
        StartControl()
        SwapPairControl()
        SpeakLastControl()
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

/// Steuerelement „Sprachen tauschen“ (Kontrollzentrum, Sperrbildschirm, Aktionstaste).
struct SwapPairControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.dolmetscher.swap") {
            ControlWidgetButton(action: SwapLanguagePairIntent()) {
                Label(WidgetTexts.text("w_swap"), systemImage: "arrow.left.arrow.right")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_swap")))
        .description(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_swap_d")))
    }
}

/// Steuerelement „Letzte Übersetzung vorlesen“.
struct SpeakLastControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.dolmetscher.speaklast") {
            ControlWidgetButton(action: SpeakLastTranslationIntent()) {
                Label(WidgetTexts.text("w_speak_last"), systemImage: "speaker.wave.2.fill")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_speak_last")))
        .description(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_speak_last_d")))
    }
}
