"""Runde 7 (Mac-App): Vertragstests für Swift-Quellen – abwärtskompatible Steuerfelder, Reset-Liste,
Umgebung der Hilfsprozesse, Einrichtungs-Fehlerarten. Reine Textprüfung, läuft überall."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = {f.name: f.read_text(encoding="utf-8") for f in (ROOT / "app").glob("*.swift")}


def test_enroll_uses_selected_mic_and_denoise():
    assert 'static func micControlValue' in APP["Engine.swift"]
    assert '["--mic", micOverride ?? Self.micControlValue' in APP["Engine.swift"]
    assert '"--denoise"' in APP["Engine.swift"]
    assert APP["Profiles.swift"].count("extraArgs: m.enrollArgs") == 2
    assert '["--model", model] + extraArgs' in APP["Profiles.swift"]


def test_clear_all_sends_clear_control_field():
    assert 'send(["clear": true])' in APP["Engine.swift"]
    assert "m.clearAll()" in APP["Views.swift"]
    assert "m.items.removeAll()" not in APP["Views.swift"]


def test_reset_covers_output_device_budget_partner_keys():
    eng = APP["Engine.swift"]
    body = eng[eng.index("func resetAllSettings"):]
    for name in ("outputDevice", "outputDeviceName", "llmBudget"):
        assert re.search(rf"\b{name} = ", body), name
    for k in ("partnerRotated", "partnerZoom"):
        assert f'"{k}"' in APP["Views.swift"][APP["Views.swift"].index("resettableKeys"):][:400]


def test_every_persisted_published_setting_is_reset():
    """Jeder @Published-Wert mit eigenem UserDefaults-Schlüssel steht in resetAllSettings (Ausnahmen begründet)."""
    eng = APP["Engine.swift"]
    body = eng[eng.index("func resetAllSettings"):]
    keys = re.findall(r'@Published var (\w+) = ud\.', eng)
    exempt = {"micName"}  # wird dort ebenfalls gesetzt, Name nur für Lesbarkeit
    missing = [k for k in keys if k not in exempt and not re.search(rf"\b{k}\b", body)]
    assert not missing, f"nicht in resetAllSettings: {missing}"


def test_latency_reset_with_runtime():
    eng = APP["Engine.swift"]
    rr = eng[eng.index("private func resetRuntime"):][:900]
    assert "latencies.removeAll()" in rr and "latencyMedian = nil" in rr


def test_bubble_equality_includes_pair():
    b = APP["BubbleViews.swift"]
    assert "a.pairKey == b.pairKey" in b
    assert "pairKey: m.mineLang + m.partnerLang" in APP["Views.swift"]


def test_bubble_a11y_mentions_number_warning_weak_mt_speaker():
    b = APP["BubbleViews.swift"]
    a11y = b[b.index("private var a11yText"):][:1400]
    for frag in ('u.numWarn', 'L.t("num_warn")', 'u.provider == "mymemory"', 'L.t("weak_mt")', "u.speaker ?? u.role"):
        assert frag in a11y, frag


def test_helper_processes_get_no_api_key():
    p = APP["Paths.swift"]
    assert "engineEnvironment(includeKey: Bool = false)" in p
    assert "Paths.engineEnvironment(includeKey: true)" in APP["Engine.swift"]
    assert "engineEnvironment()" in APP["Profiles.swift"]
    assert "includeKey: true" not in APP["Profiles.swift"]


def test_keychain_is_device_only():
    assert "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in APP["Paths.swift"]
    assert "kSecAttrAccessibleAfterFirstUnlock]" not in APP["Paths.swift"]


def test_hub_dir_follows_huggingface_hub_order_and_checks_completeness():
    s = APP["Setup.swift"]
    i_cache, i_home, i_xdg = (s.index(x) for x in ('"HF_HUB_CACHE"', '"HF_HOME"', '"XDG_CACHE_HOME"'))
    assert i_cache < i_home < i_xdg
    assert ".incomplete" in s and "snapshots" in s
    assert "HF_HOME" not in APP["Support.swift"]


def test_env_setup_refuses_second_start_and_knows_integrity():
    es = APP["EnvSetup.swift"]
    assert "proc?.isRunning == true" in es
    assert '"integrity"' in es
    sh = (ROOT / "build-support" / "setup-env.sh").read_text(encoding="utf-8")
    assert sh.index("kind=integrity") < sh.index("kind=offline")


def test_login_item_toggle_rereads_system_state():
    s = APP["SettingsView.swift"]
    assert "didBecomeActiveNotification" in s and ".onAppear { refresh() }" in s


def test_pair_swap_sends_langs_once():
    eng = APP["Engine.swift"]
    pc = eng[eng.index("private func pairChanged"):][:600]
    assert "(Langs.mine, Langs.partner) != (mineLang, partnerLang)" in pc
