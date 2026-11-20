"""Runde 21, Teil 3: Kategorien im Paketindex, Statistik je Kategorie, Verlauf: txt-Export und JSON-Import."""
import json
import pathlib
import sys

import pytest

import history_store as hs

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import make_presets_index  # noqa: E402
import preset_stats  # noqa: E402

CATS = {"health", "emergency", "transport", "food", "money", "stay", "culture", "leisure", "general"}


def test_every_pack_in_exactly_one_category():
    data = json.loads((ROOT / "tools" / "preset_categories.json").read_text(encoding="utf-8"))["categories"]
    assert set(data) == CATS
    flat = [i for ids in data.values() for i in ids]
    assert len(flat) == len(set(flat)), "Paket in mehreren Kategorien"
    packs = {p.stem for p in (ROOT / "presets").glob("*.json")}
    assert set(flat) == packs, sorted(set(flat) ^ packs)


def test_index_has_category_for_every_pack():
    idx = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]
    assert all(p["category"] in CATS for p in idx)
    assert {p["id"]: p["category"] for p in idx}["emergency"] == "emergency"
    assert {p["id"]: p["category"] for p in idx}["lost-phone"] == "emergency"


def test_safety_categories_have_critical_sentences():
    idx = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]
    for cat in ("emergency", "health"):
        assert sum(p["critical"] for p in idx if p["category"] == cat) >= 40, cat


def test_stats_by_category_adds_up(capsys):
    from _presetlib import load_packs
    rows = preset_stats.stats(load_packs())
    cats = preset_stats.by_category(rows)
    assert set(cats) <= CATS
    assert sum(c["packs"] for c in cats.values()) == len(rows)
    assert sum(c["phrases"] for c in cats.values()) == sum(r["phrases"] for r in rows)
    assert preset_stats.main(["--by-category"]) == 0
    assert "emergency" in capsys.readouterr().out
    assert preset_stats.main(["--by-category", "--format", "json"]) == 0
    assert "health" in json.loads(capsys.readouterr().out)


def test_categories_unknown_pack_defaults_to_general(tmp_path):
    (tmp_path / "tools").mkdir()
    (tmp_path / "tools" / "preset_categories.json").write_text(json.dumps({"categories": {"food": ["a"]}}))
    assert make_presets_index.categories(tmp_path) == {"a": "food"}
    assert make_presets_index.categories(tmp_path / "nein") == {}


# ---- history_store: txt und Import ------------------------------------------------------------------------------

@pytest.fixture
def st(tmp_path):
    s = hs.Store(str(tmp_path / "h.sqlite"))
    s.add("Hello", "สวัสดี", lang="en", session="s1", ts=1700000000.123456, role="me", speaker="Anna")
    s.add("Where?", None, lang="en", session="s1", ts=1700000005.0)
    s.add("ไปไหน", "Where to?\nreally", lang="th", session="s2", ts=1700000010.0)
    yield s
    s.close()


def test_txt_export_only_translations(st):
    assert "txt" in hs.FORMATS
    assert hs.export(st.rows(), "txt") == "สวัสดี\nWhere to? really\n"
    assert hs.export([], "txt") == ""


def test_import_roundtrip_and_duplicates(st, tmp_path):
    j = hs.export(st.rows(), "json")
    other = hs.Store(str(tmp_path / "o.sqlite"))
    assert other.import_json(j) == (3, 0, 0)
    assert other.import_json(j) == (0, 3, 0)               # zweiter Import: nichts doppelt
    rows = other.rows()
    assert [r["text"] for r in rows] == ["Hello", "Where?", "ไปไหน"]
    assert rows[0]["role"] == "me" and rows[0]["speaker"] == "Anna" and rows[0]["translation"] == "สวัสดี"
    assert other.search("Where to")                         # Suchindex mitgepflegt
    assert other.import_json(hs.export(st.rows(), "json")) == (0, 3, 0)
    # der Quell-Store selbst: eigener Export wird als schon vorhanden erkannt (ms-Rundung)
    assert st.import_json(j) == (0, 3, 0)
    other.close()


@pytest.mark.parametrize("text", ["", "nope", "{}", "42", "null"])
def test_import_rejects_garbage(st, text):
    with pytest.raises(ValueError):
        st.import_json(text)


def test_import_counts_bad_rows(st):
    j = json.dumps([{"time": "kaputt", "text": "x"}, {"text": "ohne zeit"}, 5, {"time": "2024-01-01T00:00:00.000Z",
                                                                                 "text": ""},
                    {"time": "2024-01-01T00:00:00.000Z", "text": "gut", "role": "evil", "confidence": "x"}])
    assert st.import_json(j) == (1, 0, 4)
    row = [r for r in st.rows() if r["text"] == "gut"][0]
    assert row["role"] is None and row["conf"] is None


def test_import_row_limit(st, monkeypatch):
    monkeypatch.setattr(hs.Store, "MAX_IMPORT_ROWS", 2)
    with pytest.raises(ValueError):
        st.import_json(json.dumps([{}] * 3))


def test_new_wave3_packs_present():
    import presets
    allp = presets.load_all()
    for pid in ("car-accident", "earthquake-evacuation", "mental-health-counseling", "sexual-health-clinic",
                "physiotherapy-injury", "mosque-visit"):
        assert pid in allp and not presets.validate(allp[pid])
    assert sum(1 for p in allp["earthquake-evacuation"]["phrases"] if p.get("critical")) >= 5
