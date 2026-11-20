// WidgetBundle.swift – Erweiterung: Schnellsätze-Widget, Steuerelement im Kontrollzentrum, Live-Aktivität.
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DolmetscherWidgets: WidgetBundle {
    var body: some Widget {
        QuickPhrasesWidget()
        StartControl()
        SwapPairControl()
        SpeakLastControl()
        ListeningToggleControl()
        EmergencyControl()
        TaxiControl()
        ListeningLiveActivity()
    }
}

/// Schalter „Zuhören“ (Kontrollzentrum): Zustand = läuft eine Live-Aktivität dieser App.
struct ListeningToggleControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { !Activity<ListeningActivityAttributes>.activities.isEmpty }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.dolmetscher.listen", provider: Provider()) { isOn in
            ControlWidgetToggle(WidgetTexts.text("w_listen"), isOn: isOn, action: ToggleListeningIntent()) { on in
                Label(WidgetTexts.text("w_listen"), systemImage: on ? "mic.fill" : "mic.slash")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_listen")))
        .description(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_listen_d")))
    }
}

/// Steuerelement „Notfall“.
struct EmergencyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.dolmetscher.emergency") {
            ControlWidgetButton(action: OpenEmergencyControlIntent()) {
                Label(WidgetTexts.text("w_emergency"), systemImage: "sos")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_emergency")))
        .description(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_emergency_d")))
    }
}

/// Steuerelement „Taxi-Karte“.
struct TaxiControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.dolmetscher.taxi") {
            ControlWidgetButton(action: OpenTaxiControlIntent()) {
                Label(WidgetTexts.text("w_taxi"), systemImage: "car.fill")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_taxi")))
        .description(LocalizedStringResource(stringLiteral: WidgetTexts.text("w_taxi_d")))
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
