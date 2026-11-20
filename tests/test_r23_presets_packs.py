"""Runde 23: die 22 neuen Pakete, Konsistenz über alle Pakete, Thai-Normalisierung, Ziffern und Währung."""
import json
import pathlib
import re
import sys
import unicodedata

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_presets  # noqa: E402

NEW = ["apartment-host-checkin", "bank-transfer-abroad", "customer-service-complaint", "diabetes-insulin",
       "diving-medical-clearance", "drugs-medication-import", "elderly-travel", "ev-charging",
       "food-poisoning-stomach", "hospital-payment-insurance", "hotel-deposit-dispute", "king-royal-respect",
       "night-train-ticket", "pharmacy-prescription-transfer", "ride-share-dispute", "sim-esim-data",
       "sprain-fracture-xray", "thai-massage-boundaries", "tourist-police-complaint", "vaccination-travel-clinic",
       "visa-run-border", "wat-donation-etiquette"]
PACKS = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "presets").glob("*.json"))}
INDEX = {p["id"]: p for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]}
INVISIBLE = re.compile("[​-‍⁠﻿ ]")
THAI_DIGIT = re.compile("[๐-๙]")


def test_all_new_packs_exist():
    assert len(NEW) >= 20 and set(NEW) <= set(PACKS)


@pytest.mark.parametrize("name", NEW)
def test_new_pack_shape(name):
    d = PACKS[name]
    assert d["style"] == "polite"
    assert 20 <= len(d["phrases"]) <= 50, name
    assert sum(1 for p in d["phrases"] if p.get("critical")) >= 5, name
    flags = [bool(p.get("critical")) for p in d["phrases"]]
    assert flags == sorted(flags, reverse=True)
    assert INDEX[name]["reviewed"] is False
    assert INDEX[name]["phrases"] == len(d["phrases"])
    assert d["note"]["de"].endswith("nicht von Muttersprachlern geprüft.")


@pytest.mark.parametrize("name", NEW)
def test_new_pack_polite_idiomatic_thai(name):
    """Höflich ohne Partikel in der Datei (die Engine setzt ครับ/ค่ะ): Bitten mit ขอ/ช่วย … หน่อย kommen vor."""
    d = PACKS[name]
    polite = [p for p in d["phrases"] if re.search(r"หน่อย|^ขอ|^ช่วย", p["th"])]
    assert len(polite) >= 2, name
    for p in d["phrases"]:
        assert not re.search("ครับ|ค่ะ|คะ|ฉัน|^ผม", p["th"]), p
        assert "?" not in p["th"] and "!" not in p["th"], p


def test_same_english_sentence_same_thai_and_critical_everywhere():
    """„Gleicher EN-Text ⇒ gleicher Thai“ (und gleiches critical) über alle Pakete, Warnungen zählen als Fehler."""
    assert check_presets.run([(n + ".json", d) for n, d in PACKS.items()]) == []
    seen = {}
    for name, d in PACKS.items():
        for p in d["phrases"]:
            k = " ".join(p["en"].split()).casefold()
            v = (p["th"], bool(p.get("critical")))
            assert seen.setdefault(k, v) == v, (name, p["en"])


def test_thai_unicode_normalisation_everywhere():
    for name, d in PACKS.items():
        texts = [d["names"]["th"]] + [p["th"] for p in d["phrases"]] + [g["th"] for g in d.get("glossary", [])]
        for t in texts:
            assert unicodedata.normalize("NFC", t) == t, (name, t)
            assert not INVISIBLE.search(t), (name, t)
            assert t == t.strip() and "  " not in t, (name, t)


def test_digits_and_currency_are_consistent():
    for name, d in PACKS.items():
        for p in d["phrases"]:
            en, th = p["en"], p["th"]
            assert not THAI_DIGIT.search(th), (name, th)                       # nie ๑๒๓
            assert "฿" not in th, (name, th)                                   # Baht als Wort
            nums_th = re.findall(r"\d+", th)
            if nums_th:
                assert sorted(nums_th) == sorted(re.findall(r"\d+", en)), (name, en, th)
            if re.search(r"\d", en) and re.search(r"\bbaht\b", en, re.I):
                assert "บาท" in th, (name, en, th)


def test_checker_flags_bad_thai_form():
    bad = {"id": "x", "names": {"de": "X", "en": "X", "th": "เอ็กซ์"}, "style": "polite",
           "phrases": [{"en": "One", "th": "สวัสดี​โลก"},
                       {"en": "Two", "th": "ต้องการ ๓ ห้อง"},
                       {"en": "It costs 50 baht.", "th": "ราคา ฿50"},
                       {"en": "Three", "th": "\u0e17\u0e34\u0e34"}]}
    res = check_presets.run([("x.json", bad)])
    msgs = " | ".join(m for _lv, _w, m in res)
    assert "unsichtbare" in msgs and "thailaendische Ziffern" in msgs and "Waehrung" in msgs
    assert "ungueltige Zeichenfolge" in msgs
