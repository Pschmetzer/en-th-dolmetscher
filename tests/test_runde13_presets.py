"""Runde 13: die Paketlisten über alle Orte (presets/*.json, presets-index.json, index.html, sw.js, docs/PRESETS.md,
READMEs, iPhone-Swift) und die Sauberkeit der Texte (Thai-Schrift, keine Dubletten im Paket)."""
import json
import pathlib
import re
import unicodedata

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "presets").glob("*.json"))}
INDEX = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SW = (ROOT / "sw.js").read_text(encoding="utf-8")
PRESETS_MD = (ROOT / "docs" / "PRESETS.md").read_text(encoding="utf-8")
THAI = re.compile("[฀-๿]")
LATIN_WORD = re.compile("[A-Za-z]{3,}")


def _js_ids(text):
    m = re.search(r"const PRESET_IDS = \[([^\]]*)\]", text)
    return re.findall(r"'([a-z0-9_-]+)'", m.group(1))


def _section(title):
    body = PRESETS_MD[PRESETS_MD.index(f"\n## {title}") + 1:]
    return body[:body.index("\n## ", 3)]


def test_web_and_service_worker_list_the_same_ids_in_the_same_order():
    web, sw = _js_ids(HTML), _js_ids(SW)
    assert web and web == sw
    assert len(web) == len(set(web))


def test_every_source_lists_exactly_the_shipped_packs():
    ids = set(FILES)
    assert len(ids) > 40
    index_ids = [p["id"] for p in INDEX]
    assert len(index_ids) == len(set(index_ids))
    assert set(index_ids) == ids, sorted(set(index_ids) ^ ids)
    assert set(_js_ids(HTML)) == ids, sorted(set(_js_ids(HTML)) ^ ids)
    doc_rows = re.findall(r"^\| `([a-z0-9_-]+)` \|", _section("Pakete"), re.M)
    assert set(doc_rows) == ids, sorted(set(doc_rows) ^ ids)
    assert len(doc_rows) == len(ids)                                                     # keine Zeile doppelt


def test_index_entries_match_the_files():
    bad = []
    for p in INDEX:
        f = FILES[p["id"]]
        if p["names"] != f["names"]:
            bad.append(f"{p['id']}: names")
        if p["phrases"] != len(f["phrases"]):
            bad.append(f"{p['id']}: phrases {p['phrases']} != {len(f['phrases'])}")
        if p["critical"] != sum(bool(x.get("critical")) for x in f["phrases"]):
            bad.append(f"{p['id']}: critical")
    assert not bad, bad


def test_web_order_follows_the_index_order():
    assert _js_ids(HTML) == [p["id"] for p in INDEX]


def test_readmes_name_only_existing_packs_with_the_right_total():
    for rel in ("README.md", "ios/README.md"):
        text = (ROOT / rel).read_text(encoding="utf-8")
        counts = {int(n) for n in re.findall(r"\b(\d+) (?:scenario|phrase) packs\b", text)}
        counts |= {int(n) for n in re.findall(r"\((\d+) packs", text)}
        assert counts == {len(FILES)}, (rel, counts)


def test_ios_pack_references_are_real_packs():
    swift = {"ScenarioPacks.swift": r"static let icons: \[String: String\] = \[(.*?)\n    \]",
             "Round6.swift": r"static let keywords: \[String: \[String\]\] = \[(.*?)\n    \]"}
    for name, rx in swift.items():
        body = re.search(rx, (ROOT / "ios" / "Dolmetscher" / name).read_text(encoding="utf-8"), re.S).group(1)
        keys = set(re.findall(r'(?:^|[,\s])"([a-z0-9-]+)": [\["]', body))
        assert keys and keys <= set(FILES), (name, sorted(keys - set(FILES)))


def _norm(s):
    s = unicodedata.normalize("NFC", s).casefold()
    return re.sub(r"[\W_]+", "", s)


@pytest.mark.parametrize("pid", sorted(FILES))
def test_pack_thai_script_and_clean_text(pid):
    p = FILES[pid]
    assert THAI.search(p["names"]["th"]), p["names"]
    for kind in ("phrases", "glossary"):
        for x in p[kind]:
            assert THAI.search(x["th"]), (pid, kind, x)                               # Thai steht im th-Feld
            assert not THAI.search(x["en"]), (pid, kind, x)                           # ... und nur dort
            assert not LATIN_WORD.search(re.sub(r"\d+|[A-Z]{2,}", "", x["th"])) or kind == "glossary", (pid, x)
            for lang in ("en", "th"):
                v = x[lang]
                assert v == v.strip() and "  " not in v and unicodedata.normalize("NFC", v) == v, (pid, repr(v))
                assert not re.search("[​‌‍﻿]", v), (pid, repr(v))      # Zero-Width-Zeichen


@pytest.mark.parametrize("pid", sorted(FILES))
def test_pack_has_no_duplicates_after_normalising(pid):
    p = FILES[pid]
    for kind in ("phrases", "glossary"):
        for lang in ("en", "th"):
            vals = [_norm(x[lang]) for x in p[kind]]
            dup = sorted({v for v in vals if vals.count(v) > 1})
            assert not dup, (pid, kind, lang, dup)
        pairs = [(_norm(x["en"]), _norm(x["th"])) for x in p[kind]]
        assert len(pairs) == len(set(pairs)), (pid, kind)


def _unsure_rows():
    rows = re.findall(r"^\| `([a-z0-9_-]+)` \| ([^|]+?) \|", _section("Unsichere Sätze (bitte zuerst prüfen)"), re.M)
    return [pytest.param(pid, sent, id=f"{pid}-{i}") for i, (pid, sent) in enumerate(rows)]


@pytest.mark.parametrize("pid, sentence", _unsure_rows())
def test_docs_unsure_sentences_exist_in_their_pack(pid, sentence):
    """„Unsichere Sätze“ in docs/PRESETS.md: Paket vorhanden und jeder Thai-Satz (Trenner " / ") steht in der Datei."""
    assert pid in FILES
    th = {x["th"] for k in ("phrases", "glossary") for x in FILES[pid][k]}
    missing = [part for part in sentence.split(" / ") if part not in th]
    assert not missing, missing
