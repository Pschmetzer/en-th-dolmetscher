"""Round 16 (iPhone app): offline mode checks that run without Xcode. The Swift tests run via xcodebuild test."""
import pathlib
import re

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")


def _src(*parts):
    return IOS.joinpath(*parts).read_text(encoding="utf-8")


def _rows():
    src = _src("Dolmetscher", "L10n+R16.swift")
    return {k: dict(re.findall(r'"(de|en|th|es|fr|ja|ko|zh-Hans|vi|id)": "((?:[^"\\]|\\.)*)"', body))
            for k, body in re.findall(r'"((?:off|err)_[a-z_]+)": \[(.*?)\],?\n(?=        "|    \])', src, re.S)}


def test_texts_complete_in_all_languages_with_same_placeholders():
    rows = _rows()
    assert len(rows) >= 20
    for key, row in rows.items():
        assert set(row) == set(LANGS), key
        assert all(v.strip() for v in row.values()), key
        ph = re.findall(r"%[@d]", row["en"])
        assert all(re.findall(r"%[@d]", v) == ph for v in row.values()), key


def test_keys_used_by_the_views_exist_and_table_is_wired():
    rows = _rows()
    names = ("OfflinePacksView.swift", "OfflineReadiness.swift", "Views.swift", "Model.swift", "WhisperEngine.swift")
    src = "".join(_src("Dolmetscher", n) for n in names)
    used = set(re.findall(r'"((?:off|err)_[a-z_]+)"', src))
    own = {k for k in used if k in rows or k.startswith("off_")}
    assert own <= set(rows), own - set(rows)
    assert "err_offline_only" in rows
    assert "round16" in _src("Dolmetscher", "L10n.swift")


def test_offline_only_gates_every_network_path():
    assert "onlineAllowed" in _src("Dolmetscher", "Model.swift")
    assert not re.search(r"translate\([^)]*allowOnline: allowOnline\)", _src("Dolmetscher", "Model.swift"))
    assert "OfflineMode.setting()" in _src("Dolmetscher", "Tools.swift")
    assert "OfflineMode.setting()" in _src("Dolmetscher", "WhisperEngine.swift")
    assert "OfflineMode" in _src("Dolmetscher", "Intents.swift")
    assert "err_offline_only" in _src("Dolmetscher", "Round8.swift")  # error gets a Settings button
    assert "off_only_banner" in _src("Dolmetscher", "Views.swift")  # clearly shown in the conversation
    assert "OfflinePacksView" in _src("Dolmetscher", "SettingsView.swift")


def test_logic_file_has_no_ui_or_system_imports_and_is_tested():
    logic = _src("Dolmetscher", "OfflineReadiness.swift")
    for bad in ("import SwiftUI", "import Speech", "import Translation", "import AVFoundation"):
        assert bad not in logic, bad
    tests = _src("DolmetscherTests", "OfflineReadinessTests.swift")
    for name in ("OfflineReport", "OfflineMode", "travelWarning", "phrasebookAlwaysOffline"):
        assert name in tests, name


def test_status_colours_only_via_status_colour():
    for n in ("OfflinePacksView.swift", "OfflineReadiness.swift"):
        assert not re.search(r"\.(green|orange|red|blue)\b", _src("Dolmetscher", n)), n
