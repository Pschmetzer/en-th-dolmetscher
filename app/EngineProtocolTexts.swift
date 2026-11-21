// EngineProtocolTexts.swift – Tabellen „Protokollcode -> Text-Schlüssel“ (aus Engine.swift herausgelöst, Runde 27, ohne
// Verhaltensänderung). Reine Daten, nur Foundation, getestet in swift-tests (Abdeckung gegen docs/PROTOKOLL.md).
import Foundation

enum EngineProtocolTexts {
    /// Codes, deren `msg` eine wechselnde Ursache enthält: im Hinweis zusätzlich zum übersetzten Text zeigen.
    static let errorDetailCodes: Set<String> = ["translate_failed", "mic_failed", "mic_unavailable",
                                                "mic_list_failed", "ffmpeg_missing", "file_failed", "file_empty",
                                                "profiles_failed", "preset_invalid"]
    /// `error.code` (docs/PROTOKOLL.md) -> L10n-Schlüssel. Literale Schlüssel: tests/test_l10n_keys.py prüft sie.
    static let errorKeys: [String: String] = [
        "mic_denied": "err_mic_denied", "mic_unavailable": "err_mic_unavailable", "mic_no_data": "err_mic_no_data",
        "mic_timeout": "err_mic_timeout", "mic_failed": "err_mic_failed", "mic_not_found": "err_mic_not_found",
        "output_not_found": "err_output_not_found", "output_unsupported": "err_output_unsupported",
        "output_invalid": "err_output_not_found", "offline_mt_missing": "err_offline_mt_missing",
        "preset_invalid": "err_preset_invalid", "vad_failed": "err_vad_failed", "python_env_broken": "crash_env",
        "profile_name_invalid": "err_profile_name_invalid", "profile_invalid": "err_profile_invalid",
        "profile_not_found": "err_profile_not_found", "profile_delete_failed": "err_profile_delete_failed",
        "history_failed": "err_history_failed", "history_days_invalid": "err_history_days_invalid",
        "mic_list_failed": "err_mic_list_failed", "mic_file_missing": "err_mic_file_missing",
        "ffmpeg_missing": "err_ffmpeg_missing", "audio_missing": "err_audio_missing", "model_offline": "err_model_offline",
        "disk_full": "err_disk_full", "log_unavailable": "err_log_unavailable",
        "translate_failed": "err_translate_failed", "llm_billing": "err_llm_billing", "reassign_expired": "err_reassign_expired",
        "reassign_empty": "err_reassign_empty", "reassign_invalid": "err_reassign_invalid",
        "phrase_invalid": "err_phrase_invalid", "edit_invalid": "err_edit_invalid",
        "voice_unknown": "err_voice_unknown", "glossary_invalid": "err_glossary_invalid", "langs_invalid": "err_langs_invalid",
        "file_empty": "err_file_empty", "file_failed": "err_file_failed",
        "profiles_failed": "err_speaker_model", "speak_invalid": "err_speak_invalid",
        "llm_budget": "err_llm_budget", "mic_invalid": "err_mic_invalid",
        "system_audio_missing": "err_system_audio_missing",
    ]
    /// Status zu `dropped.code`; fehlt ein Code hier, gilt der allgemeine Text („dropped“).
    static let droppedKeys: [String: String] = [
        "too_short": "drop_too_short", "other_language": "drop_other_language", "locked": "drop_locked",
        "paused": "paused", "unsure": "drop_unsure", "hallucination": "dropped", "filler": "dropped",
        "empty": "dropped", "error": "drop_error", "other": "dropped",
    ]
    /// Codes ohne Statusänderung: Antwort kommt als `command`, `translate_failed` folgt als `error`, `stopped` ist still.
    static let silentDroppedCodes: Set<String> = ["command", "translate_failed", "stopped"]
}
