"""Runde 21, Mac-App: Regressionswächter für Quelltext-Eigenschaften (kein Live-Lauf)."""
import pathlib
import re

APP = pathlib.Path(__file__).resolve().parent.parent / "app"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_history_opens_main_window_by_identifier():
    s = src("HistoryView.swift")
    assert "w.identifier == Prefs.mainWindowID" in s
    assert 'w.title == L.t("app_title")' not in s


def test_engine_runner_has_sigkill_fallback_and_cleanup():
    s = src("Profiles.swift")
    assert "SIGKILL" in s
    assert "readabilityHandler = nil" in s
    assert "nicht startbar" in s


def test_check_python_drains_pipes():
    s = src("Paths.swift")
    assert "LockedBuffer" in s
    assert "errBuf" in s and "outBuf" in s


def test_stop_button_uses_accessible_red():
    s = src("BubbleViews.swift")
    assert ".background(LangStyle.fillRed, in: Capsule())" in s
    assert "Color.red, in: Capsule()" not in s


def test_ui_state_survives_language_switch():
    s = src("Views.swift")
    assert "final class UIDrafts" in s
    assert "@State private var query" not in s
    assert ".id(uiLang)" in s


def test_toolbar_has_three_variants():
    s = src("Views.swift")
    start = s.index("ViewThatFits(in: .horizontal) {")
    body = s[start:s.index("compactMenu\n            }\n            // Sehr schmal")]
    assert body.count("startButton") >= 2


def test_stop_speaking_icon_differs_from_mute():
    s = src("Views.swift")
    assert 'Image(systemName: "stop.circle")' in s


def test_level_bar_traits_and_log_scale():
    s = src("Views.swift")
    assert "enum LevelScale" in s and "log10" in s
    assert ".updatesFrequently" in s


def test_glossary_file_private():
    s = src("Engine.swift")
    assert "0o600" in s and "glossary_save_failed" in s


def test_no_blocking_sleep_in_new_helpers():
    # checkPython darf nur kurz (50 ms) schlafen, nie in Schleifen
    s = src("Paths.swift")
    assert "usleep" not in s
    assert not re.search(r"while[^\n]*Thread\.sleep", s)


def test_partner_buttons_rotate_with_text():
    s = src("PartnerView.swift")
    assert s.count("rotationEffect(.degrees(rotated ? 180 : 0))") >= 3


def test_clipboard_translate_wired():
    assert "translateClipboard()" in src("Engine.swift")
    assert "reg(6) { [weak model] in model?.translateClipboard() }" in src("HotKeys.swift")
    assert "ClipboardLogic.prepare" in src("Engine.swift")
    assert "translate_clipboard" in src("DolmetscherApp.swift")


def test_system_voice_volume_uses_logic():
    assert "VolumeLogic.systemVoice(volume)" in src("Engine.swift")


def test_diagnostic_report_is_english():
    s = src("Support.swift")
    for de in ("verweigert", "nicht gefragt", "Modelle im Cache", "Mikrofon-Berechtigung"):
        assert de not in s, de
    assert "Microphone permission: " in s


def test_service_for_selected_text():
    build = (APP.parent / "build.sh").read_text(encoding="utf-8")
    assert "<key>NSServices</key>" in build and "<string>translateSelection</string>" in build
    app = src("DolmetscherApp.swift")
    assert "func translateSelection(_ pboard: NSPasteboard" in app
    assert "NSApp.servicesProvider = TranslateService.shared" in app
    assert "func translateText(_ raw: String?)" in src("Engine.swift")


def test_hotkeys_configurable_and_mini_mode():
    hk = src("HotKeys.swift")
    assert "HotKeyLogic.configured()" in hk and "func setLetter" in hk
    assert "HotKeyLogic.actions" in src("SettingsView.swift")
    assert 'id: "mini"' in src("DolmetscherApp.swift")
    assert "struct MiniView" in src("MiniView.swift")
    ids = {a for a in re.findall(r"Action\(id: (\d+)", src("HotKeyLogic.swift"))}
    assert ids == {"1", "2", "3", "4", "5", "6"}


def test_text_requested_before_ready_is_spoken_after_ready():
    e = src("Engine.swift")
    assert "pendingSay = (text, lang)" in e
    assert "if let p = pendingSay { pendingSay = nil; say(p.text, lang: p.lang) }" in e
