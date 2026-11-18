"""Runde 8: neue Korpusdateien tests/corpus/r8-*.json (Zahlen, Namen/Orte, Höflichkeit, Notfall, Satzteilung,
Umgangssprache). Die Dateien laufen zusätzlich automatisch durch tests/test_corpus.py; hier stehen die
Struktur-Zusagen und eine Gegenprobe: ein verfälschter Zahlenwert in der Übersetzung muss auffallen."""
import json
import pathlib
import re

import pytest

import dolmetscher as d

CORPUS = pathlib.Path(__file__).resolve().parent / "corpus"
FILES = sorted(CORPUS.glob("r8-*.json"))
DATA = {f.stem: json.loads(f.read_text(encoding="utf-8")) for f in FILES}
ALL = [c for v in DATA.values() for c in v["cases"]]
THEMEN = {"r8-zahlen", "r8-namen-orte", "r8-hoeflichkeit", "r8-notfall", "r8-satzteilung", "r8-umgangssprache"}


@pytest.fixture
def pair():
    old = list(d.PAIR)

    def use(src, dst):
        assert d.set_pair(src, dst), (src, dst)
    yield use
    d.set_pair(*old)


def test_alle_themen_vorhanden_mit_mindestens_40_faellen():
    assert set(DATA) == THEMEN
    for name, v in DATA.items():
        assert len(v["cases"]) >= 40, name


def test_ids_eindeutig_und_mit_dateiname_als_praefix():
    ids = [c["id"] for c in ALL]
    assert len(ids) == len(set(ids))
    for name, v in DATA.items():
        assert all(c["id"].startswith(name + "-") for c in v["cases"]), name


def test_thai_referenzen_als_maschinell_ungeprueft_gekennzeichnet():
    for v in DATA.values():
        assert v["reviewed"] is False and "ungeprüft" in v["about"]
    for c in ALL:
        assert bool(c.get("machine")) == ("th" in (c["src"], c["dst"])), c["id"]


def test_sprachabdeckung_je_thema():
    for name, v in DATA.items():
        srcs = {c["src"] for c in v["cases"]}
        assert {"en", "th"} <= srcs, name
    assert {c["src"] for c in DATA["r8-zahlen"]["cases"]} == {"de", "en", "th"}
    assert {c["dst"] for c in ALL} == {"de", "en", "th"}


def test_keine_doppelten_quellsaetze_je_richtung():
    keys = [(c["src"], c["dst"], c["text"]) for c in ALL]
    assert len(keys) == len(set(keys))


def test_zahlenfaelle_enthalten_ziffern_und_notfall_nummern():
    assert all(re.search(r"\d", c["text"]) for c in DATA["r8-zahlen"]["cases"])
    notfall = " ".join(c["text"] + c["translation"] for c in DATA["r8-notfall"]["cases"])
    assert all(n in notfall for n in ("191", "1669", "1155"))


def test_satzteilung_enthaelt_abkuerzungen_und_mehrere_saetze():
    cases = DATA["r8-satzteilung"]["cases"]
    abk = re.compile(r"\b(Dr|Mr|Mrs|Prof|Nr|No|ca|approx|Rd|St|Rm|Fri|Mon|Sat|Mt|Tel|z\. B|i\.e|etc)\.|นพ\.|ดร\.|ถ\.|บจก\.")
    assert sum(bool(abk.search(c["text"])) for c in cases) >= 30
    assert sum(len(re.findall(r"[.!?] ", c["text"])) >= 1 for c in cases) >= 25


def _zahl_verfaelschen(text):
    """Letzte mehrstellige Zahl um 1 erhöhen (Ziffernfolge bleibt gleich lang)."""
    ms = [m for m in re.finditer(r"\d{2,}", text)]
    if not ms:
        return None
    m = ms[-1]
    return text[:m.start()] + str(int(m.group()) + 1) + text[m.end():]


ZAHLEN = [c for c in DATA["r8-zahlen"]["cases"] if _zahl_verfaelschen(c["translation"]) and "," not in c["translation"]
          and ":" not in c["translation"]]


def test_gegenprobe_hat_genug_faelle():
    assert len(ZAHLEN) >= 20


@pytest.mark.parametrize("case", ZAHLEN, ids=[c["id"] for c in ZAHLEN])
def test_verfaelschte_zahl_faellt_auf(case, pair):
    pair(case["src"], case["dst"])
    assert not d.numbers_differ(case["text"], case["translation"])
    assert d.numbers_differ(case["text"], _zahl_verfaelschen(case["translation"]))
