# ruff: noqa: E501
"""Runde 27 (Web): 17 neue Pakete, Lautschrift fuer alle Pakete, Verweise statt Dubletten, Pruefstand im Satzbuch."""
import json
import pathlib
import re
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_presets  # noqa: E402
import preset_dupes  # noqa: E402
import preset_lint  # noqa: E402
import preset_rom  # noqa: E402
from _presetlib import load_packs  # noqa: E402

NEW = ["air-pollution-haze", "asthma-inhaler", "card-payment-surcharge", "chao-phraya-river-boat", "epipen-anaphylaxis",
       "hotel-theft-report", "jellyfish-marine-sting", "locksmith-lockout", "online-shopping-delivery", "phone-repair-shop",
       "power-outage-blackout", "seafood-by-weight", "snake-bite-venomous", "stray-dogs-safety", "tipping-service-charge",
       "traffic-fine-police-ticket", "two-price-attraction-tickets"]
PACKS = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "presets").glob("*.json"))}
INDEX = {p["id"]: p for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]}
CATS = json.loads((ROOT / "tools" / "preset_categories.json").read_text(encoding="utf-8"))["categories"]
SAFETY = {"health", "emergency"}


def test_seventeen_new_packs_and_total():
    assert len(NEW) == 17 and set(NEW) <= set(PACKS)
    assert len(PACKS) >= 243 and len(INDEX) == len(PACKS)


@pytest.mark.parametrize("name", NEW)
def test_new_pack_shape_and_index(name):
    d = PACKS[name]
    assert d["style"] == "polite" and 15 <= len(d["phrases"]) <= 50 and len(d["glossary"]) >= 8
    flags = [bool(p.get("critical")) for p in d["phrases"]]
    assert flags == sorted(flags, reverse=True)
    cat = next(c for c, ids in CATS.items() if name in ids)
    if cat in SAFETY:
        assert sum(flags) >= 5
    assert INDEX[name]["reviewed"] is False and INDEX[name]["phrases"] == len(d["phrases"])
    assert d["note"]["de"].endswith("nicht von Muttersprachlern geprüft.") and d["note"]["en"].endswith("not checked by native speakers.")
    assert len(d["note"]["de"]) <= 500 and len(d["note"]["en"]) <= 500
    assert INDEX[name].get("keywords_de") and INDEX[name].get("keywords_th")
    assert not re.search("[A-Za-z]", d["names"]["th"])


def test_checker_and_linter_are_clean_on_all_packs():
    assert check_presets.run(load_packs()) == []
    assert preset_lint.lint(load_packs()) == []


def test_rom_is_filled_for_every_sentence_and_valid():
    for name, d in PACKS.items():
        assert preset_rom.check_rom(name + ".json", d) == [], name
        missing = [p["en"] for p in d["phrases"] if not isinstance(p.get("rom"), str) or not p["rom"].strip()]
        assert not missing, (name, missing[:3])


def test_package_size_budgets_still_hold_with_rom():
    sizes = {n: (ROOT / "presets" / (n + ".json")).stat().st_size for n in PACKS}
    assert max(sizes.values()) <= 22_000 and sum(sizes.values()) <= 1_900_000


def test_dupes_tool_adds_see_also_once_and_is_idempotent():
    assert preset_dupes.apply(load_packs()) == []          # schon eingearbeitet: nichts mehr zu tun
    assert preset_dupes.main(["--check"]) == 0
    d = PACKS["pharmacy"]["note"]
    assert "Siehe auch:" in d["de"] and "See also:" in d["en"] and d["de"].endswith("geprüft.") and d["en"].endswith("speakers.")
    assert all(len(p["note"]["de"]) <= 500 and len(p["note"]["en"]) <= 500 for p in PACKS.values() if "note" in p)


def test_dupes_tool_logic(tmp_path):
    def mk(i, names, en):
        return (i + ".json", {"id": i, "names": names, "note": {"de": "Hinweis. Thai-Sätze maschinell erstellt.", "en": "Note. Thai lines machine-made."},
                              "phrases": [{"en": x, "th": "ก"} for x in en]})
    a = mk("a", {"de": "A", "en": "A"}, ["one", "two", "three", "x"])
    b = mk("b", {"de": "B", "en": "B"}, ["one", "two", "three", "y"])
    c = mk("c", {"de": "C", "en": "C"}, ["z"])
    packs = [a, b, c]
    assert preset_dupes.overlaps(packs) == [(3, "a", "b")]
    assert preset_dupes.apply(packs) == ["a.json", "b.json"]
    assert a[1]["note"]["de"] == "Hinweis. Siehe auch: B. Thai-Sätze maschinell erstellt."
    assert preset_dupes.apply(packs) == []


def test_review_status_line_in_book_and_texts_in_three_languages():
    from _webhelpers import SCRIPT, web_str
    assert "function reviewLine(" in SCRIPT and "reviewLine(id, d);" in SCRIPT and "rv: !!p.reviewed" in SCRIPT
    S = web_str()
    for lg in ("de", "en", "th"):
        assert "{p}" in S[lg]["revStat"] and S[lg]["revHint"].strip() and S[lg]["tagSet"].strip(), lg


def test_pack_counts_and_docs():
    n = len(PACKS)
    for f in ("README.md", "docs/ARCHITEKTUR.md", "llms.txt", "docs/PRESETS.md", "ios/README.md", "docs/th/README.md", "docs/th/WEB.md"):
        assert "%d " % n in (ROOT / f).read_text(encoding="utf-8"), f
    assert "Web, round 27" in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    doc = (ROOT / "docs" / "PRESETS.md").read_text(encoding="utf-8")
    assert all("`%s`" % pid in doc for pid in NEW)
