"""Runde 8: neue Hilfe-Dokumente. Genannte Pfade müssen existieren, Markdown-Links dürfen nicht ins Leere gehen,
und die genannten Kürzel und Sprachbefehle müssen im Code stehen."""
import pathlib
import re

import pytest

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
DE = ["FAQ", "FEHLERHILFE", "SCHNELLSTART", "TASTENKUERZEL", "SPRACHBEFEHLE", "DATENSCHUTZ-KURZ"]
EN = ["FAQ", "TROUBLESHOOTING", "QUICKSTART", "SHORTCUTS", "VOICE-COMMANDS", "PRIVACY-SHORT"]
FILES = [ROOT / "docs" / f"{n}.md" for n in DE] + [ROOT / "docs" / "en" / f"{n}.md" for n in EN]
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)\)")
CODE = re.compile(r"`([^`\n]+)`")
REPO_PREFIX = ("docs/", "app/", "ios/", "tests/", "build-support/", "presets/", "bench/")
REPO_ROOT_FILES = {p.name for p in ROOT.iterdir() if p.is_file()}


@pytest.mark.parametrize("path", FILES, ids=lambda p: str(p.relative_to(ROOT)))
def test_file_exists_and_not_empty(path):
    assert path.is_file()
    assert len(path.read_text(encoding="utf-8")) > 500


@pytest.mark.parametrize("path", FILES, ids=lambda p: str(p.relative_to(ROOT)))
def test_markdown_links_resolve(path):
    broken = []
    for target in LINK.findall(path.read_text(encoding="utf-8")):
        if re.match(r"^(https?:|mailto:|#)", target):
            continue
        rel = target.split("#", 1)[0]
        if rel and not (path.parent / rel).resolve().exists():
            broken.append(target)
    assert not broken, f"{path.name}: broken links {broken}"


@pytest.mark.parametrize("path", FILES, ids=lambda p: str(p.relative_to(ROOT)))
def test_named_repo_paths_exist(path):
    missing = []
    for token in CODE.findall(path.read_text(encoding="utf-8")):
        t = token.strip()
        if " " in t or t.startswith(("~", "-", "$", "/")):
            continue
        if t.startswith(REPO_PREFIX) or (t in REPO_ROOT_FILES) or re.fullmatch(r"[\w.-]+\.(py|sh|html|js|json|md|swift)", t):
            name = t.rstrip("/")
            if "*" in name:
                continue
            found = (ROOT / name).exists() or any(ROOT.glob(f"**/{name}")) if "/" not in name else (ROOT / name).exists()
            if not found and name not in {"history.json", "history.sqlite", "setup.log", "engine.log", "glossary.txt",
                                          "learn.json", "phrases.json", "anthropic_key", "localStorage"}:
                missing.append(t)
    assert not missing, f"{path.name}: paths not in the repo {missing}"


def test_german_and_english_pairs_cross_link():
    for de, en in zip(DE, EN):
        assert (ROOT / "docs" / "en" / f"{en}.md").is_file() and (ROOT / "docs" / f"{de}.md").is_file()
        assert f"en/{en}.md" in (ROOT / "docs" / f"{de}.md").read_text(encoding="utf-8")
        assert f"{de}.md" in (ROOT / "docs" / "en" / f"{en}.md").read_text(encoding="utf-8")


def test_global_hotkeys_documented_as_in_code():
    code = (ROOT / "app" / "HotKeys.swift").read_text(encoding="utf-8")
    doc = (ROOT / "docs" / "TASTENKUERZEL.md").read_text(encoding="utf-8")
    for combo in re.findall(r'name: "(⌃⌥[A-Z])"', code):
        assert combo in doc, combo


def test_menu_shortcuts_exist_in_code():
    code = (ROOT / "app" / "DolmetscherApp.swift").read_text(encoding="utf-8")
    for key in ('"z"', '"e"', '"f"', '"p"', '"t"', '"r"', ".return", '"."'):
        assert f"keyboardShortcut({key}" in code, key


def test_web_keys_exist_in_index_html():
    html = (ROOT / "index.html").read_text(encoding="utf-8")
    for code in ("KeyE", "KeyT", "KeyP", "KeyL", "Digit1", "Digit2", "Space", "Escape"):
        assert code in html, code


@pytest.mark.parametrize("phrase,key", [
    ("pause", "pause"), ("resume", "resume"), ("unmute", "resume"), ("repeat", "repeat"), ("slower", "slower"),
    ("faster", "faster"), ("louder", "louder"), ("quieter", "quieter"), ("thai only", "thai"),
    ("english only", "english"), ("auto", "auto"), ("female voice", "female"), ("male voice", "male"),
    ("english off", "en_off"), ("thai off", "th_off"), ("english on", "en_on"), ("thai on", "th_on"),
    ("translate both", "both_on"), ("clear", "clear"), ("help", "help"), ("volume 3", "volume:3"),
    ("speed 5", "speed:5"), ("german only", "only:de"), ("too loud", "quieter"), ("mute off", "resume"),
])
def test_documented_voice_commands_are_recognised(phrase, key):
    assert d.parse_command(phrase) == key


def test_wake_words_and_length_limit():
    assert d.match_wake("Translator, pause") == "pause"
    assert d.match_wake("Hey translator resume") is not None
    assert d.parse_command("one two three four five six") is None
    assert d.CMD_MAX_WORDS == 5


def test_docs_name_the_same_wake_word_and_limit():
    de = (ROOT / "docs" / "SPRACHBEFEHLE.md").read_text(encoding="utf-8")
    en = (ROOT / "docs" / "en" / "VOICE-COMMANDS.md").read_text(encoding="utf-8")
    assert f"höchstens {d.CMD_MAX_WORDS} Wörter" in de
    assert f"at most {d.CMD_MAX_WORDS} words" in en
