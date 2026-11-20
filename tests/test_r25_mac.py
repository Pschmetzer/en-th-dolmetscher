"""Runde 25, Mac-App: Fenster-Kennungen, Textetabellen (de/en/th), Kürzel-Katalog gegen den Code, Verdrahtung der neuen Teile."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def table_rows(file, enum):
    """{key: {lang: text}} aus einer Swift-Tabelle der Form `"key": ["de": "...", "en": "...", "th": "..."]`."""
    s = src(file)
    body = s[re.search(r"static let (?:r23Table|table)", s).start():]
    rows = {}
    for m in re.finditer(r'"([A-Za-z0-9_]+)":\s*\[((?:"[a-z]{2}":\s*"(?:\\.|[^"\\])*",?\s*)+)\]', body):
        rows[m.group(1)] = dict(re.findall(r'"([a-z]{2})":\s*"((?:\\.|[^"\\])*)"', m.group(2)))
    return rows


def test_window_catalog_matches_scenes():
    scenes = re.findall(r'^\s*Window\([^\n]*?id:\s*"([a-z]+)"\)\s*\{', src("DolmetscherApp.swift"), re.M)
    ids = re.findall(r'Entry\(id:\s*"([a-z]+)"', src("WindowCatalog.swift"))
    assert scenes, "keine Fenster-Szenen gefunden"
    assert sorted(scenes) == sorted(ids), (scenes, ids)


def test_smoke_test_covers_every_window():
    ids = re.findall(r'Entry\(id:\s*"([a-z]+)"', src("WindowCatalog.swift"))
    smoke = src("SmokeTest.swift")
    missing = [i for i in ids if f'case "{i}":' not in smoke]
    assert not missing, missing


def test_open_window_calls_use_known_ids():
    ids = set(re.findall(r'Entry\(id:\s*"([a-z]+)"', src("WindowCatalog.swift")))
    used = set()
    for f in APP.glob("*.swift"):
        used |= set(re.findall(r'openWindow\(id:\s*"([a-z]+)"\)', f.read_text(encoding="utf-8")))
    assert used <= ids, used - ids


def test_r23_r24_r25_tables_have_three_languages():
    thai = re.compile("[฀-๿]")
    for file in ("L10n+R23.swift", "L10n+R23b.swift", "L10n+R24.swift", "L10n+R25.swift"):
        rows = table_rows(file, None)
        assert len(rows) > 5, file
        for key, row in rows.items():
            assert all(row.get(lg, "").strip() for lg in ("de", "en", "th")), (file, key, sorted(row))
            assert thai.search(row["th"]), (file, key, "th ohne Thai-Schrift")


def test_r25_placeholders_match_across_languages():
    ph = re.compile(r"%(?:\.\d+)?[@dfs]")
    for key, row in table_rows("L10n+R25.swift", None).items():
        sets = {lg: sorted(ph.findall(t)) for lg, t in row.items()}
        # Reihenfolge darf sich zwischen Sprachen ändern, die Menge nicht
        assert sets["de"] == sets["en"] == sets["th"], (key, sets)


def test_r25_keys_used_in_code_exist():
    rows = table_rows("L10n+R25.swift", None)
    used = set()
    for f in APP.glob("*.swift"):
        used |= set(re.findall(r'\bR25T\.[tf]\(\s*"([A-Za-z0-9_]+)"', f.read_text(encoding="utf-8")))
    assert used, "R25T wird nirgends benutzt"
    assert used <= set(rows), sorted(used - set(rows))


def test_advice_hint_keys_exist_in_l10n_or_r25():
    l10n = src("L10n.swift")
    r25 = table_rows("L10n+R25.swift", None)
    hints = set(re.findall(r'hintKey:\s*"([a-z_]+)"', src("ErrorAdviceLogic.swift")))
    assert hints
    missing = [h for h in sorted(hints) if f'"{h}":' not in l10n and h not in r25]
    assert not missing, missing


def test_advice_step_labels_cover_all_steps():
    steps = re.search(r"enum Step: Hashable \{ case ([^}]+)\}", src("ErrorAdviceLogic.swift")).group(1)
    names = [s.strip() for s in steps.split(",")]
    r8 = src("Runde8.swift")
    label = r8[r8.index("static func label"):r8.index("@MainActor static func run")]
    run = r8[r8.index("@MainActor static func run"):r8.index("struct ErrorBanner")]
    for n in names:
        assert f".{n}" in label, f"{n}: kein Knopftext"
        assert f".{n}" in run, f"{n}: keine Aktion"


def _catalog_shortcuts():
    out = {}
    for m in re.finditer(r'keys:\s*"([^"]+)",\s*labelKey:\s*"([^"]+)"', src("ShortcutCatalog.swift")):
        out[m.group(1)] = m.group(2)
    return out


def _code_shortcuts():
    keys = set()
    mods = {".command": "⌘", ".option": "⌥", ".shift": "⇧", ".control": "⌃"}
    for f in APP.glob("*.swift"):
        for m in re.finditer(r'keyboardShortcut\("(.)",\s*modifiers:\s*(\[[^\]]*\]|\.\w+)\)', f.read_text(encoding="utf-8")):
            found = re.findall(r"\.\w+", m.group(2))
            ms = "".join(sorted((mods[x] for x in found if x in mods), key="⌃⌥⇧⌘".index))
            keys.add(ms + m.group(1).upper())
    return keys


def test_shortcut_catalog_entries_exist_in_code():
    """Jedes einfache Kürzel im Kürzel-Fenster ist wirklich belegt (sonst zeigt das Fenster ein totes Kürzel)."""
    code = _code_shortcuts()
    bad = []
    for keys in _catalog_shortcuts():
        if re.fullmatch(r"[⌃⌥⇧⌘]+[A-Z/.]", keys) and keys not in code:
            bad.append(keys)
    assert not bad, bad


def test_no_duplicate_shortcuts_in_menu_commands():
    s = src("DolmetscherApp.swift")
    seen = {}
    for m in re.finditer(r'keyboardShortcut\(([^)\n]*)\)', s):
        k = re.sub(r"\s+", "", m.group(1))
        if k.startswith("KeyEquivalent"):
            continue   # Schleife der Schnellsätze (⌘1–⌘9)
        # Hauptfenster-Menü: je Kürzel einmal (Toggle-Varianten mit gleichem Kürzel gibt es nicht)
        seen.setdefault(k, 0)
        seen[k] += 1
    dups = {k: n for k, n in seen.items() if n > 1 and k not in (".return,modifiers:.command", ".cancelAction", ".defaultAction")}
    assert not dups, dups


def test_new_logic_files_have_no_ui_imports():
    for name in ("ErrorAdviceLogic.swift", "SearchDebounce.swift", "BilingualExport.swift", "AudioRouteLogic.swift", "WindowCatalog.swift"):
        text = src(name)
        assert re.search(r"^import Foundation$", text, re.M), name
        assert not re.search(r"^import (SwiftUI|AppKit)", text, re.M), name


def test_new_logic_files_are_linked_into_swift_tests():
    links = pathlib.Path(ROOT / "swift-tests" / "Sources" / "DolmetscherLogic")
    for name in ("ErrorAdviceLogic", "SearchDebounce", "BilingualExport", "AudioRouteLogic", "WindowCatalog"):
        assert (links / f"{name}.swift").is_symlink(), name


def test_history_search_is_debounced_and_exports_two_columns():
    h = src("HistoryView.swift")
    assert "queryDraft" in h and "debouncer.schedule" in h
    assert "HistoryTableExport.save" in h
    assert "filter.query" in h
    assert "$filter.query" not in h, "Suchfeld darf nicht mehr direkt an den Filter gebunden sein"


def test_handoff_is_opt_in_and_declared():
    assert "NSUserActivityTypes" in (ROOT / "build.sh").read_text(encoding="utf-8")
    assert "de.dolmetscher.conversation" in (ROOT / "build.sh").read_text(encoding="utf-8")
    r24 = src("R24Views.swift")
    assert "HandoffPayload.shouldAdvertise" in r24
    assert "onContinueUserActivity" in r24
    assert 'prefKey = "handoffEnabled"' in src("ShortcutCatalog.swift")
    assert "private var on = false" in src("SettingsR25.swift")


def test_settings_view_stays_split():
    n = len(src("SettingsView.swift").splitlines())
    assert n < 700, n
    for name in ("SettingsAudioSections.swift", "SettingsAPIKey.swift", "SettingsR25.swift", "SettingsQuickPhrases.swift"):
        assert (APP / name).exists(), name


def test_new_views_have_accessibility_basics():
    r25 = src("SettingsR25.swift")
    assert r25.count("accessibilityLabel") >= 2
    assert "isHeader" in r25
    r24 = src("R24Views.swift")
    assert "accessibilityElement(children: .combine)" in r24
    assert r24.count('R24T.t("show_big") + ": "') >= 3, "Knöpfe „Groß zeigen“ brauchen den Betrag im Label"
