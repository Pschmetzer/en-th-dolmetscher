"""Runde 23, Mac-App: Texte der eigenen Tabelle app/L10n+R23b.swift (R23T) und Verdrahtung der neuen Funktionen."""

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"
LANGS = ("de", "en", "th")
THAI = re.compile("[฀-๿]")
PLACEHOLDER = re.compile(r"%(?:\.\d+)?[@dfs]")
LITERAL = re.compile(r'"((?:\\.|[^"\\])*)"')


def table():
    src = (APP / "L10n+R23b.swift").read_text(encoding="utf-8")
    body = src[src.index("static let table") :]
    rows = {}
    for m in re.finditer(r'^\s*"([a-z0-9_]+)": \[(.*?)\],\s*$', body, re.S | re.M):
        pass
    # Zeilenweise: ein Eintrag beginnt mit "key": [ und endet mit ],
    for m in re.finditer(r'"([a-z0-9_]+)": \[((?:"(?:de|en|th)": "(?:\\.|[^"\\])*",?\s*)+)\],', body):
        row = dict(re.findall(r'"(de|en|th)": "((?:\\.|[^"\\])*)"', m.group(2)))
        assert m.group(1) not in rows, f"doppelt: {m.group(1)}"
        rows[m.group(1)] = row
    return rows


def used_keys():
    keys = set()
    for f in APP.glob("*.swift"):
        keys |= set(re.findall(r'\bR23T\.[tf]\(\s*"([a-z0-9_]+)"', f.read_text(encoding="utf-8")))
    return keys


def test_table_has_entries_and_all_languages():
    rows = table()
    assert len(rows) > 60
    bad = {
        k: [lg for lg in LANGS if not r.get(lg, "").strip()]
        for k, r in rows.items()
        if len(r) != 3 or not all(r.values())
    }
    assert not bad, bad


def test_thai_is_thai():
    bad = [k for k, r in table().items() if not THAI.search(r["th"]) and r["th"] != r["en"]]
    assert not bad, bad


def test_placeholders_match():
    bad = {
        k: [PLACEHOLDER.findall(r[lg]) for lg in LANGS]
        for k, r in table().items()
        if len({tuple(PLACEHOLDER.findall(r[lg])) for lg in LANGS}) > 1
    }
    assert not bad, bad


def test_used_keys_exist():
    missing = sorted(used_keys() - set(table()))
    assert not missing, missing


def test_dynamic_keys_exist():
    """Schlüssel, die über Hilfsfunktionen (Rückgabe "keytest_ok" usw.) geliefert werden."""
    src = (APP / "R23SetViews.swift").read_text(encoding="utf-8")
    dyn = set(re.findall(r'"((?:mictest|keytest)_[a-z]+)"', src))
    assert dyn and dyn <= set(table()), sorted(dyn - set(table()))


def test_no_unused_keys():
    src = "\n".join(f.read_text(encoding="utf-8") for f in APP.glob("*.swift") if f.name != "L10n+R23b.swift")
    literals = set(re.findall(r'"([a-z0-9_]+)"', src))
    unused = sorted(k for k in table() if k not in literals)
    assert not unused, unused


def test_logic_is_linked_into_swift_tests():
    link = ROOT / "swift-tests" / "Sources" / "DolmetscherLogic" / "R23SetLogic.swift"
    assert link.is_symlink() and link.resolve() == APP / "R23SetLogic.swift"
    assert (ROOT / "swift-tests" / "Tests" / "DolmetscherLogicTests" / "R23SetLogicTests.swift").exists()


def test_logic_has_no_ui_imports():
    src = (APP / "R23SetLogic.swift").read_text(encoding="utf-8")
    imports = set(re.findall(r"^import (\w+)", src, re.M))
    assert imports == {"Foundation"}, imports


def test_no_secret_in_report_and_preview_code():
    """Die Fehlermeldung und die Vorschau lesen weder den Schlüsselbund noch Gesprächsdaten."""
    logic = (APP / "R23SetLogic.swift").read_text(encoding="utf-8")
    assert "APIKeyStore" not in logic and "Keychain" not in logic
    assert "items" not in re.search(r"enum R23Report.*?\n}\n", logic, re.S).group(0)


def test_help_menu_and_wiring():
    app = (APP / "DolmetscherApp.swift").read_text(encoding="utf-8")
    for needle in (
        "help_onboarding",
        "help_whatsnew",
        "help_report",
        "sensitive_menu",
        "ScreenLockWatcher.shared.start",
        'id: "whatsnew"',
        "menu_last_header",
    ):
        assert needle in app, needle
    assert "SettingsResetRow(group:" in (APP / "SettingsView.swift").read_text(encoding="utf-8")
    hist = (APP / "HistoryView.swift").read_text(encoding="utf-8")
    for needle in ("R23StatsDashboard", "exportMerged", "facetMenu", "List(selection: $multi)"):
        assert needle in hist, needle
    assert "MicTestRow" in (APP / "Onboarding.swift").read_text(encoding="utf-8")
    assert "PreflightNote" in (APP / "EnvSetup.swift").read_text(encoding="utf-8")
    assert "failureDetails" in (APP / "HotKeys.swift").read_text(encoding="utf-8")


def test_screen_lock_uses_distributed_notifications():
    src = (APP / "R23SetViews.swift").read_text(encoding="utf-8")
    assert "com.apple.screenIsLocked" in src and "com.apple.screenIsUnlocked" in src
