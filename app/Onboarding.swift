// Onboarding.swift – Einrichtungsschritte im Willkommensdialog: Mikrofon erklären und freigeben, Sprachpaar,
// Modellgröße (Empfehlung nach Hardware), optionaler Claude-Schlüssel und der Test-Satz „Sag etwas“.
import AVFoundation
import SwiftUI

enum HardwareInfo {
    static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "" }
        return String(cString: buf)
    }

    static var ramGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }

    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return sysctlString("hw.optional.arm64") == "1"      // Rosetta
        #endif
    }

    static var recommendedModel: String {
        OnboardingLogic.recommendedModel(ramGB: ramGB, arm64: isAppleSilicon,
                                         chip: sysctlString("machdep.cpu.brand_string"))
    }
}

struct OnboardingSteps: View {
    @ObservedObject var m: EngineModel
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var baseline = 0

    private var testPhase: String {
        OnboardingLogic.testPhase(micAuthorized: mic == .authorized, listening: m.active,
                                  heard: m.items.count > baseline)
    }

    private var testKey: String {
        switch testPhase {
        case "done": return "onb_test_done"
        case "say": return "onb_test_say"
        case "start": return "onb_test_start"
        default: return "onb_test_mic"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            micStep
            pairStep
            modelStep
            keyStep
            testStep
        }
        .onAppear { baseline = m.items.count }
    }

    private func head(_ icon: String, _ key: String) -> some View {
        Label(L.t(key), systemImage: icon).font(.headline)
    }

    private func note(_ key: String) -> some View {
        Text(L.t(key)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Mikrofon

    private var micStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            head("mic.fill", "onb_mic_title")
            note(mic == .authorized ? "onb_mic_ok" : mic == .notDetermined ? "onb_mic_why" : "onb_mic_denied")
            if mic == .notDetermined {
                Button(L.t("onb_mic_allow")) { askMic() }
            } else if mic != .authorized {
                Button(L.t("onb_mic_open")) { openMicSettings() }
            } else {
                MicTestRow(m: m)          // Runde 23: Pegel prüfen, bevor es losgeht
            }
        }
    }

    private func askMic() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            mic = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    private func openMicSettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    // MARK: Sprachpaar und Modell

    private var pairStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            head("globe", "onb_pair_title")
            HStack {
                Picker(L.t("onb_pair_mine"), selection: $m.mineLang) { langOptions }
                Picker(L.t("onb_pair_partner"), selection: $m.partnerLang) { langOptions }
            }
        }
    }

    @ViewBuilder private var langOptions: some View {
        ForEach(Langs.codes, id: \.self) { Text(Langs.label($0)).tag($0) }
    }

    private var modelStep: some View {
        let rec = HardwareInfo.recommendedModel
        return VStack(alignment: .leading, spacing: 6) {
            head("cpu", "onb_model_title")
            Picker(L.t("model_label"), selection: $m.model) {
                ForEach(["auto", "small", "medium", "best"], id: \.self) { Text(modelName($0)).tag($0) }
            }
            Text(L.f("onb_model_recommended", modelName(rec), Int(HardwareInfo.ramGB.rounded())))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(ModelCache.hint(model: m.model, thai: Langs.hasThai)).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func modelName(_ code: String) -> String { L.t(code == "auto" ? "model_auto" : "model_" + code) }

    // MARK: Schlüssel und Test

    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            head("key", "onb_key_title")
            note(APIKeyStore.exists ? "setup_key_ok" : "onb_key_text")
            Button(L.t("onb_open_settings")) { openSettingsWindow() }
            if APIKeyStore.exists { KeyTestRow() }   // Runde 23: Schlüssel prüfen
        }
    }

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            head("waveform", "onb_test_title")
            note(testKey)
            HeadphoneHintRow(m: m)                   // Runde 23: Kopfhörer gegen Echo
            if testPhase == "start" { Button(L.t("onb_test_button")) { m.startListening() } }
            if testPhase == "say" { Button(L.t("onb_test_stop")) { m.stopListening() } }
        }
    }
}
