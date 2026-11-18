"""Runde 13: Thai-Dokumentation vorhanden, gekennzeichnet, verlinkt und mit den Quellen abgeglichen."""
import json
import pathlib
import re

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
TH_DIR = ROOT / "docs" / "th"
NAMES = ["README.md", "QUICKSTART.md", "FAQ.md", "PRIVACY-SHORT.md"]
TH_FILES = [TH_DIR / n for n in NAMES]
PACKS = len(list((ROOT / "presets").glob("*.json")))
LANGUAGES = len(json.loads((ROOT / "languages.json").read_text(encoding="utf-8"))["languages"])
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)\)")
PACK_COUNT = re.compile(r"\b(\d+)\s+(?:ชุดสถานการณ์|ชุดวลี|scenario packs?|phrase packs?)")
LANG_COUNT = re.compile(r"\b(\d+)\s+(?:ภาษา|languages)\b")
NOTICE_TH = "ยังไม่ได้รับการตรวจโดยเจ้าของภาษา"
NOTICE_EN = "not been checked by native speakers"


def _text(path):
    return path.read_text(encoding="utf-8")


@pytest.mark.parametrize("path", TH_FILES, ids=lambda p: p.name)
def test_file_exists_and_notice_at_top(path):
    assert path.is_file()
    head = "\n".join(_text(path).splitlines()[:8])
    assert NOTICE_TH in head and NOTICE_EN in head
    assert "../MUTTERSPRACHLER.md" in head
    assert (ROOT / "docs" / "MUTTERSPRACHLER.md").is_file()


@pytest.mark.parametrize("path", TH_FILES, ids=lambda p: p.name)
def test_markdown_links_resolve(path):
    bad = []
    for target in LINK.findall(_text(path)):
        if target.startswith(("http://", "https://", "#")):
            continue
        rel = target.split("#")[0]
        if rel and not (path.parent / rel).resolve().exists():
            bad.append(target)
    assert not bad, bad


@pytest.mark.parametrize("path", TH_FILES, ids=lambda p: p.name)
def test_repo_paths_in_code_exist(path):
    missing = []
    for ref in re.findall(r"`([A-Za-z0-9_./-]+\.(?:xcodeproj|md|json|sh))`", _text(path)):
        if "/" in ref and not ref.startswith("~") and not (ROOT / ref).exists():
            missing.append(ref)
    assert not missing, missing


@pytest.mark.parametrize("path", TH_FILES, ids=lambda p: p.name)
def test_counts_match_sources(path):
    text = _text(path)
    assert not [m for m in PACK_COUNT.findall(text) if int(m) != PACKS]
    assert not [m for m in LANG_COUNT.findall(text) if int(m) != LANGUAGES]


def test_counts_are_stated():
    assert f"{LANGUAGES} ภาษา" in _text(TH_DIR / "README.md")
    assert f"{PACKS} ชุด" in _text(TH_DIR / "README.md")
    assert f"{LANGUAGES} ภาษา" in _text(TH_DIR / "FAQ.md")


def test_exact_identifiers_match_english_quickstart():
    en = _text(ROOT / "docs" / "en" / "QUICKSTART.md")
    th = _text(TH_DIR / "QUICKSTART.md")
    for token in ("./build.sh --install", "~/Applications/Dolmetscher.app", "xcode-select --install",
                  "com.pschmetzer.dolmetscher", "https://pschmetzer.github.io/en-th-dolmetscher/",
                  "open ios/Dolmetscher.xcodeproj", "3.5 GB", "Python 3.12"):
        assert token in en and token in th, token


def test_privacy_paths_match_english():
    en = _text(ROOT / "docs" / "en" / "PRIVACY-SHORT.md")
    th = _text(TH_DIR / "PRIVACY-SHORT.md")
    for token in re.findall(r"`([^`]*(?:Library|--)[^`]*)`", en):
        assert token in th, token


def test_cross_links():
    assert "docs/th/README.md" in _text(ROOT / "README.md")
    for name in ("QUICKSTART.md", "FAQ.md", "PRIVACY-SHORT.md"):
        assert f"../th/{name}" in _text(ROOT / "docs" / "en" / name)
        assert f"../en/{name}" in _text(TH_DIR / name)
    assert "../../README.md" in _text(TH_DIR / "README.md")
