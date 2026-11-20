// ErrorAdviceLogic.swift – zu jedem Fehlercode der Engine ein konkreter nächster Schritt (Ein-Klick-Aktionen im
// Hinweisband). Reine Logik, nur Foundation; getestet in swift-tests. Die Knöpfe selbst stehen in Runde8.swift.
import Foundation

enum ErrorAdviceLogic {
    enum Step: Hashable { case micSettings, appSettings, restart, log, retryAfterNetwork, networkSettings, storageSettings, help }

    struct Advice: Equatable { var hintKey: String; var steps: [Step] }

    /// Text-Schlüssel (L10n bzw. R25T) mit dem Handlungsvorschlag und die passenden Schritte; nil für unbekannte Codes.
    static func advice(for code: String?) -> Advice? {
        switch code {
        case "mic_denied": return Advice(hintKey: "advice_mic_denied", steps: [.micSettings])
        case "mic_unavailable", "mic_no_data", "mic_timeout", "mic_failed", "mic_not_found", "mic_invalid", "mic_list_failed":
            return Advice(hintKey: "advice_mic_device", steps: [.appSettings, .restart])
        case "model_offline": return Advice(hintKey: "advice_model_offline", steps: [.retryAfterNetwork, .networkSettings])
        case "offline_mt_missing": return Advice(hintKey: "advice_offline_mt", steps: [.appSettings])
        case "llm_billing", "llm_budget": return Advice(hintKey: "advice_llm_key", steps: [.appSettings])
        case "translate_failed": return Advice(hintKey: "advice_translate_failed", steps: [.appSettings, .log])
        case "output_not_found", "output_unsupported", "output_invalid": return Advice(hintKey: "advice_output", steps: [.appSettings])
        case "python_env_broken", "vad_failed", "profiles_failed", "ffmpeg_missing", "audio_missing":
            return Advice(hintKey: "advice_env", steps: [.restart, .log])
        case "disk_full": return Advice(hintKey: "advice_disk_full", steps: [.storageSettings, .log])
        case "history_failed", "file_failed", "file_empty": return Advice(hintKey: "advice_file", steps: [.log, .help])
        case "langs_invalid", "languages_invalid": return Advice(hintKey: "advice_langs", steps: [.appSettings])
        default: return nil
        }
    }

    /// Schritte, die die Engine neu starten.
    static func restartsEngine(_ s: Step) -> Bool { s == .restart || s == .retryAfterNetwork }

    /// Adresse zu den Schritten, die nur eine Seite der Systemeinstellungen oder die Hilfe öffnen.
    static func url(for s: Step) -> URL? {
        switch s {
        case .micSettings: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .networkSettings: return URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")
        case .storageSettings: return URL(string: "x-apple.systempreferences:com.apple.settings.Storage")
        case .help: return URL(string: DiagnosticsLogic.helpURL)
        default: return nil
        }
    }
}
