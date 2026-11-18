"""Runde 11: Zahlen und Kürzel in der Doku müssen zu den Dateien und zum Code passen."""
import json
import pathlib
import re

import pytest

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOC_FILES = [ROOT / "README.md", ROOT / "CONTRIBUTING.md", ROOT / "ios" / "README.md",
             *sorted((ROOT / "docs").glob("*.md")), *sorted((ROOT / "docs" / "en").glob("*.md"))]
PACKS = len(list((ROOT / "presets").glob("*.json")))
LANGUAGES = len(json.loads((ROOT / "languages.json").read_text(encoding="utf-8"))["languages"])
PACK_COUNT = re.compile(r"\b(\d+)\s+(?:scenario packs?|phrase packs?|Phrasenpakete|Szenario-Pakete)\b")
LANG_COUNT = re.compile(r"\b(\d+)\s+(?:languages|Sprachen)\b")


def _read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_source_counts_agree():
    index = json.loads(_read("presets-index.json"))["packs"]
    assert len(index) == PACKS
    assert len(d.LANGS) == LANGUAGES


@pytest.mark.parametrize("path", DOC_FILES, ids=lambda p: str(p.relative_to(ROOT)))
def test_pack_count_in_docs(path):
    wrong = [m for m in PACK_COUNT.findall(path.read_text(encoding="utf-8")) if int(m) != PACKS]
    assert not wrong, f"{path.name}: {wrong}, die Dateien in presets/ sind {PACKS}"


@pytest.mark.parametrize("path", DOC_FILES, ids=lambda p: str(p.relative_to(ROOT)))
def test_language_count_in_docs(path):
    text = path.read_text(encoding="utf-8")
    wrong = [m for m in LANG_COUNT.findall(text) if int(m) != LANGUAGES]
    # "10 Sprachen/languages" der iPhone-Oberfläche und Teilmengen (Allergiekarte) sind gewollt andere Zahlen
    subset = r"(?:allerg|interface|Oberfläche)[^.\n]*\b{}\s+(?:languages|Sprachen)\b"
    wrong = [m for m in wrong if not re.search(subset.format(m), text, re.I)]
    assert not wrong, f"{path.name}: {wrong}, languages.json hat {LANGUAGES}"


def test_changelog_latest_pack_total_is_current():
    totals = re.findall(r"\((\d+) in total", _read("CHANGELOG.md"))
    assert totals and max(int(t) for t in totals) == PACKS


def test_readmes_agree_on_scenario_packs():
    for rel in ("README.md", "ios/README.md"):
        assert f"{PACKS} scenario packs" in _read(rel), rel


MODS = {".command": "⌘", ".shift": "⇧", ".option": "⌥", ".control": "⌃"}


def _combos(swift_rel):
    code = _read(swift_rel)
    out = set()
    for m in re.finditer(r'keyboardShortcut\(([^,)]+)(?:,\s*modifiers:\s*([^)]*\]|[^)]*))?\)', code):
        key, mods = m.group(1).strip(), (m.group(2) or "")
        if mods.strip() in ("", "[]"):
            continue
        sym = "".join(MODS[k] for k in (".control", ".option", ".shift", ".command") if k in mods)
        if key == ".return":
            out.add(sym + "Return")
        elif re.fullmatch(r'"(.)"', key):
            out.add(sym + key.strip('"').upper())
    return out


def _doc_combos(rel):
    return set(re.findall(r"[⌃⌥⇧⌘]+(?:Return|[A-Z0-9.+/=-])", _read(rel)))


def test_mac_menu_shortcuts_are_all_documented():
    in_code = _combos("app/DolmetscherApp.swift") | _combos("app/PartnerView.swift")
    # ⌘1 bis ⌘9 und ⌥⌘1 bis ⌥⌘9 entstehen aus KeyEquivalent(Character(...)) und stehen als Bereich in der Doku
    assert len(in_code) >= 15
    for rel in ("docs/TASTENKUERZEL.md", "docs/en/SHORTCUTS.md"):
        missing = in_code - _doc_combos(rel)
        assert not missing, f"{rel}: {sorted(missing)}"


def test_documented_mac_shortcuts_exist_in_code():
    in_code = _combos("app/DolmetscherApp.swift") | _combos("app/PartnerView.swift")
    hotkeys = set(re.findall(r'name: "(⌃⌥[A-Z])"', _read("app/HotKeys.swift")))
    digits = {f"⌘{i}" for i in range(1, 10)} | {f"⌥⌘{i}" for i in range(1, 10)}
    allowed = in_code | hotkeys | digits | {"⌘=", "⌘C"} | _combos("ios/Dolmetscher/Views.swift")
    for rel in ("docs/TASTENKUERZEL.md", "docs/en/SHORTCUTS.md"):
        unknown = _doc_combos(rel) - allowed
        assert not unknown, f"{rel}: {sorted(unknown)}"


def test_iphone_shortcuts_documented():
    in_code = _combos("ios/Dolmetscher/Views.swift")
    assert in_code == {"⌘Return", "⌘B", "⌘/"}
    for rel in ("docs/TASTENKUERZEL.md", "docs/en/SHORTCUTS.md"):
        text = _read(rel)
        assert in_code <= _doc_combos(rel), rel
        assert "keine Tastenkürzel" not in text and "no keyboard shortcuts" not in text


def test_architecture_names_every_module_and_helper():
    arch = _read("docs/ARCHITEKTUR.md")
    names = [p.name for p in ROOT.glob("*.py")]
    names += [p.name for p in (ROOT / "ios" / "Dolmetscher").glob("Round*.swift")]
    names += [p.name for p in (ROOT / "tools").glob("*.py") if not p.name.startswith("_")]
    missing = [n for n in names if n not in arch]
    assert not missing, missing


def test_privacy_statements_match_code():
    doc = _read("docs/DATENSCHUTZ.md")
    ios_model = _read("ios/Dolmetscher/Model.swift")
    # Live-Aktivität: neue Installation aus, gesperrt ohne Sätze
    assert "LivePrivacy.initialSetting" in ios_model
    live = next(line for line in doc.splitlines() if line.startswith("- **Live-Aktivität**"))
    assert "Standard bei neuer Installation: aus" in live and "Standard: an" not in live
    assert "Live Activity** (off by default" in _read("README.md")
    # Zwischenablage: lokal und 120 s, Standard an
    secure = _read("ios/Dolmetscher/Round8.swift")
    assert "lifetime: TimeInterval = 120" in secure and ".localOnly: true" in secure
    assert 'clipboardExpires = d.object(forKey: "clipboardExpires") as? Bool ?? true' in ios_model
    assert "nach 2 Minuten" in doc
    # Bildschirmaufnahme: Mac sharingType, iPhone isCaptured, beide Standard aus
    assert "sharingType" in doc and "UIScreen.isCaptured" in doc
    assert 'hideOnCapture = d.object(forKey: "hideOnCapture") as? Bool ?? false' in ios_model
    # Echo-Schutz: nur Arbeitsspeicher
    assert "_SPOKEN = collections.deque(maxlen=8)" in _read("dolmetscher.py")
    assert "nur im Arbeitsspeicher" in doc and d.ECHO["on"] is True
