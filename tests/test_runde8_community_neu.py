"""Runde 8 (Community): Vorlagen, Richtliniendateien, Store-Texte und Roadmap sind da und halten die Limits."""
from pathlib import Path

import re

import pytest

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / ".github" / "ISSUE_TEMPLATE"
STORE = ROOT / "docs" / "store"
PLATFORMS = ("mac", "iphone")
LANGS = ("de", "en", "th")
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "description": 4000, "whats_new": 4000}
STORE_FILES = tuple(LIMITS)
NEW_TEMPLATES = ("bug-report.yml", "feature-request.yml", "phrase-review.yml")


def test_community_dateien_vorhanden():
    for rel in (
        ".github/pull_request_template.md",
        "SECURITY.md",
        "CODE_OF_CONDUCT.md",
        "docs/MUTTERSPRACHLER.md",
        "docs/ROADMAP.md",
        "docs/store/README.md",
    ):
        p = ROOT / rel
        assert p.is_file(), rel
        assert len(p.read_text(encoding="utf-8").strip()) > 200, rel


@pytest.mark.parametrize("name", NEW_TEMPLATES)
def test_community_vorlage_frontmatter(name):
    text = (TEMPLATES / name).read_text(encoding="utf-8")
    for key in ("name", "description", "title", "labels", "body"):
        assert re.search(rf"^{key}:", text, re.M), (name, key)
    assert re.search(r'^labels: \[".+"\]$', text, re.M), name
    ids = re.findall(r"^    id: (\S+)$", text, re.M)
    assert ids and len(ids) == len(set(ids)), name
    assert "required: true" in text, name
    types = re.findall(r"^  - type: (\S+)$", text, re.M)
    assert set(types) <= {"markdown", "input", "textarea", "dropdown", "checkboxes"}, name
    assert text.count("label:") >= len(ids) - types.count("checkboxes"), name
    assert "\t" not in text, name


def test_community_pr_vorlage_checkliste():
    text = (ROOT / ".github" / "pull_request_template.md").read_text(encoding="utf-8")
    assert text.count("- [ ]") >= 5
    assert "CHANGELOG" in text and "DATENSCHUTZ" in text


@pytest.mark.parametrize("platform", PLATFORMS)
@pytest.mark.parametrize("lang", LANGS)
def test_community_store_texte_und_limits(platform, lang):
    for stem in STORE_FILES:
        p = STORE / platform / lang / f"{stem}.txt"
        assert p.is_file(), p
        text = p.read_text(encoding="utf-8").strip()
        assert text, p
        assert len(text) <= LIMITS[stem], (p, len(text))


def test_community_store_stichwoerter_ohne_leerzeichen():
    for platform in PLATFORMS:
        for lang in LANGS:
            kw = (STORE / platform / lang / "keywords.txt").read_text(encoding="utf-8").strip()
            assert " " not in kw and ",," not in kw and not kw.endswith(","), (platform, lang)


def test_community_roadmap_ist_als_ideen_gekennzeichnet():
    text = (ROOT / "docs" / "ROADMAP.md").read_text(encoding="utf-8")
    assert "Ideen" in text and "keine Zusagen" in text
