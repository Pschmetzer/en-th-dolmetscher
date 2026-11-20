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
    assert "engineEnvironment(includeKey: Bool = false, historyPassword: Bool = false)" in p
    # Runde 21: auch die Engine bekommt den Schlüssel nicht mehr in der Umgebung (ps eww), sondern per stdin
    assert "Paths.engineEnvironment(includeKey: true)" not in APP["Engine.swift"]
    assert '["api_key": key]' in APP["Engine.swift"]
    # Runde 26: nur Verlauf-Aufrufe bekommen das Verlauf-Passwort
    assert "engineEnvironment(historyPassword: HistoryPasswordLogic.needsEnv(args: args))" in APP["Profiles.swift"]
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


# ---- zweite Runde: Features und Verbesserungen -------------------------------------------------

def test_release_flag_disables_dev_override_and_plain_key_copy():
    p = APP["Paths.swift"]
    assert "#if RELEASE_BUILD" in p and p.count("#if RELEASE_BUILD") >= 3
    sh = (ROOT / "build.sh").read_text(encoding="utf-8")
    assert '-D RELEASE_BUILD' in sh and 'SWIFT_FLAGS+=(-D RELEASE_BUILD)' in sh


def test_build_sh_release_requires_notarization_or_flag():
    sh = (ROOT / "build.sh").read_text(encoding="utf-8")
    assert "--no-notarize" in sh and "-unnotarized" in sh
    assert "notarytool log" in sh and "stapler validate" in sh and "spctl -a -vv" in sh
    assert "hdiutil create" in sh and "dsymutil" in sh and "otool -L" in sh
    assert "CFBundleURLTypes" in sh and "whatsnew.json" in sh
    assert "swiftc" in sh and " -g " in sh


def test_setup_env_progress_and_update_path():
    sh = (ROOT / "build-support" / "setup-env.sh").read_text(encoding="utf-8")
    assert "echo \"progress $pct\"" in sh and "REUSE=1" in sh
    assert "--offline --find-links" in sh


def test_mic_usage_text_not_tied_to_english_thai():
    sh = (ROOT / "build.sh").read_text(encoding="utf-8")
    assert "Englisch und Thai übersetzen" not in sh


def test_new_control_fields_only_clear_and_known_flags():
    # Engine-Seite: nur {"clear": true} ist neu abgesprochen; alle anderen Felder gab es schon
    assert 'send(["clear": true])' in APP["Engine.swift"]
    assert '"forget"' not in "\n".join(APP.values())


def test_file_translation_uses_engine_flags():
    eng = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
    e = APP["Engine.swift"]
    for flag in ('"--file"', '"--mute"', '"--langs"'):
        assert flag in e, flag
        assert f"add_argument({flag}" in eng, flag


def test_menu_and_url_scheme_wired():
    d = APP["DolmetscherApp.swift"]
    assert "applicationShouldTerminate" in d and "application(_ app: NSApplication, open urls" in d
    assert ".keyboardShortcut(KeyEquivalent(Character(" in d
    assert 'Window(L.t("caption_title"), id: "caption")' in d
    x = APP["Extras.swift"]
    for cmd in ('"start"', '"stop"', '"pause"', '"say"'):
        assert cmd in x
    assert "text.count <= 1000" in x and "Langs.valid(" in x and "urlAllowed" in x


def test_pair_strings_have_pair_variants():
    rows = APP["L10n.swift"]
    used = set(re.findall(r'L\.tp\("([a-z_]+)"', "\n".join(APP.values())))
    used |= {"reassign_me", "reassign_other"}
    for k in used:
        assert f'"{k}_pair"' in rows, k
        assert f'"{k}"' in rows, k


def test_md_escape_and_dur_in_export():
    s = APP["Support.swift"]
    assert "func mdEscape" in s and "mdEscape(u.text)" in s
    assert "u.dur" in s
    assert "u.dur = (o[\"dur\"]" in APP["Engine.swift"]


def test_hung_engine_auto_restart_and_wake():
    e = APP["Engine.swift"]
    assert "hungRestartAfter" in e and "hungRestarts < 3" in e and "func systemDidWake" in e
    assert "didWakeNotification" in APP["Extras.swift"] and "kAudioHardwarePropertyDevices" in APP["Extras.swift"]


def test_setup_space_checks_both_volumes():
    es = APP["EnvSetup.swift"]
    assert "separateVolumes" in es and "freeBytes(at: modelsURL)" in es


def test_translate_helper_accepts_pairs():
    h = (ROOT / "tools" / "translate-helper" / "main.swift").read_text(encoding="utf-8")
    assert '"--pairs"' in h and "requestedPairs" in h
    assert "--check" in APP["Extras.swift"] and "--pairs" in APP["Extras.swift"]
