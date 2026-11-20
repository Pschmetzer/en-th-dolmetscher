"""Runde 21, Teil 4: Suche, Qualitaetsbericht, Routen und Stichwoerter im Index, Verlauf-Statistik."""
import json
import pathlib
import sys

import pytest

import history_store as hs

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import preset_quality  # noqa: E402
import preset_search  # noqa: E402
from _presetlib import load_packs  # noqa: E402

INDEX = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))


def test_index_keywords_and_routes():
    ids = {p["id"] for p in INDEX["packs"]}
    for p in INDEX["packs"]:
        assert isinstance(p["keywords"], list) and len(p["keywords"]) <= 12
        assert all(k == k.lower() and k.strip() for k in p["keywords"])
    assert set(INDEX["routes"]) >= {"backpacker-2-weeks", "family-with-kids", "digital-nomad", "medical-tourism"}
    for rid, r in INDEX["routes"].items():
        assert set(r["names"]) == {"de", "en", "th"}, rid
        assert r["packs"] and len(r["packs"]) == len(set(r["packs"])), rid
        assert set(r["packs"]) <= ids, (rid, set(r["packs"]) - ids)
    assert "emergency" in INDEX["routes"]["backpacker-2-weeks"]["packs"]


def test_search_finds_in_all_languages_and_filters_critical():
    packs = load_packs()
    en = preset_search.search(packs, "TOURIST police")
    assert any(h["pack"] == "police" for h in en)
    th = preset_search.search(packs, "ตำรวจท่องเที่ยว")
    assert th and all("ตำรวจท่องเที่ยว" in h["th"] or h["where"] == "name" for h in th)
    crit = preset_search.search(packs, "ambulance", critical_only=True)
    assert crit and all(h["where"] == "phrase" and h["critical"] for h in crit)
    assert preset_search.search(packs, "   ") == [] and preset_search.search(packs, "qqqzzz") == []


def test_search_cli(capsys):
    assert preset_search.main(["ambulance", "--limit", "2", "--json"]) == 0
    assert len(json.loads(capsys.readouterr().out)) == 2
    assert preset_search.main(["qqqzzz"]) == 1


def test_quality_report_shape_and_penalties(tmp_path):
    rows = preset_quality.report(load_packs())
    assert len(rows) == len(INDEX["packs"]) and rows == sorted(rows, key=lambda r: (r["score"], r["id"]))
    assert all(0 <= r["score"] <= 100 and not r["reviewed"] for r in rows)
    d = tmp_path / "p"
    d.mkdir()
    pack = {"id": "bad", "names": {"de": "x", "en": "x", "th": "ก"}, "style": "polite",
            "glossary": [{"en": "gate", "th": "ก"}],
            "phrases": [{"en": "Call 1669", "th": "โทร 191"}, {"en": "a" * 120, "th": "ก" * 120}]}
    (d / "bad.json").write_text(json.dumps(pack), encoding="utf-8")
    r = preset_quality.report(load_packs(str(d)))[0]
    assert r["number_mismatch"] == 1 and r["long"] == 1 and r["score"] < 80


def test_quality_cli_min_score(capsys):
    assert preset_quality.main([]) == 0
    assert "kategorie" in capsys.readouterr().out
    assert preset_quality.main(["--min-score", "101"]) == 1
    capsys.readouterr()
    assert preset_quality.main(["--json"]) == 0 and json.loads(capsys.readouterr().out)


@pytest.fixture
def st(tmp_path):
    s = hs.Store(str(tmp_path / "h.sqlite"))
    day = 1700000000.0
    for i, txt in enumerate(["Hello there", "Hello there", "How much?", "ไปไหน"]):
        s.add(txt, "x", lang="en", session="a", ts=day + i)
    s.add("Next day sentence here", None, session="b", ts=day + 86400)
    yield s
    s.close()


def test_history_stats(st):
    r = st.stats()
    assert r["total"] == 5 and r["sessions"] == 2
    assert r["per_day"]["2023-11-14"] == {"utterances": 4, "words": 2 + 2 + 2 + 1}
    assert r["per_day"]["2023-11-15"] == {"utterances": 1, "words": 4}
    assert r["top_sentences"] == [{"text": "Hello there", "count": 2}]
    assert r["first"] < r["last"]
    shifted = st.stats(tz_offset_s=7 * 3600)                # Thailand: 05:13 Uhr -> gleicher Tag, 29:13 -> naechster
    assert sum(d["utterances"] for d in shifted["per_day"].values()) == 5


def test_history_stats_empty(tmp_path):
    s = hs.Store(str(tmp_path / "e.sqlite"))
    assert s.stats() == {"total": 0, "sessions": 0, "first": None, "last": None, "per_day": {}, "top_sentences": []}
    s.close()


def test_retention_default_unchanged_and_suggested_option(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    rec = hs.Recorder()
    assert rec.keep_days is None                              # Standard bleibt unbegrenzt (dokumentiert)
    assert rec.enable(True) and rec.keep_days is None
    assert rec.enable(True, keep_days="suggested") and rec.keep_days == hs.SUGGESTED_KEEP_DAYS == 30
    rec.store.close()



def test_new_wave7_packs():
    import presets
    allp = presets.load_all()
    for pid in ("meditation-retreat", "hill-tribe-trekking", "night-train-sleeper", "rock-climbing", "scuba-course",
                "tea-coffee-plantation"):
        assert pid in allp and not presets.validate(allp[pid])
