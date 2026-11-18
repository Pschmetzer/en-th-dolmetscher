"""Runde 15: inhaltliche Qualität aller Phrasenpakete (presets/*.json) als Regeln, die auf JEDEM Paket laufen.

Geprüft werden Englisch und Deutsch (Sätze, Namen, Kulturhinweise), die Kennzeichnung kritischer Sätze, Notrufnummern
und formale Thai-Fehler. Der Thai-Inhalt selbst wird hier nicht bewertet."""
import json
import pathlib
import re
import sys
import unicodedata

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_presets  # noqa: E402

PACKS = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "presets").glob("*.json"))}
NAMES = sorted(PACKS)

MAX_EN = 120
THAI = re.compile("[฀-๿]")
SENTENCE_END = re.compile(r"(?<=[.?!])\s+")
QUESTION_OPENER = re.compile(
    r"^(do|does|did|is|are|am|can|could|would|will|where|what|how|when|which|who|why|may|should|have|has)\b", re.I)
NOT_A_QUESTION = re.compile(r"^(do not|have a)\b", re.I)
EMERGENCY = re.compile(
    r"ambulance|call the police|call the tourist police|\bthere is a fire\b|cannot breathe|chest pain|drown|"
    r"\bhelp!|(this|it) is an emergency|call a doctor|need a doctor|gas smell|smell gas|attacked|robbed|"
    r"someone is following|was drugged|drink was spiked", re.I)
NOT_CRITICAL = re.compile(r"how much|receipt|discount|refund|invoice|opening hours|menu", re.I)
US_SPELLING = re.compile(r"anesthe|diarrhea|\btires?\b|diaper|stroller|gas station|\bcolor|\bcenter\b|\bcheck, please|"
                         r"\blicense\b|pediatric|favorite|jewelry|\btraveler|\btrunk\b(?! of)", re.I)
INFORMAL_DE = re.compile(r"\b(du|dich|dir|dein\w*|euch|eure?\w*)\b")
MACHINE_DE = "Thai-Sätze maschinell erstellt, nicht von Muttersprachlern geprüft."
MACHINE_EN = "Thai lines machine-made, not checked by native speakers."
NUMBER_LABELS = {  # Notrufnummer -> Beschriftung, die in der Nähe stehen muss
    "191": r"polizei|police",
    "199": r"feuer|fire",
    "1669": r"rettung|ambulance",
    "1155": r"tourist ?police|touristenpolizei",
}
UNIT = re.compile(
    r"\d[\d.,]*(?:[–-]\d[\d.,]*)?\s*(?:baht|prozent|per cent|tage|days|stunden|hours?|uhr|"
    r"monat\w*|months?|wochen)", re.I)


def _texts(d):
    """Alle englischen und deutschen Texte eines Pakets mit Fundort."""
    out = [("names.de", d["names"]["de"]), ("names.en", d["names"]["en"]),
           ("note.de", d["note"]["de"]), ("note.en", d["note"]["en"])]
    out += [("phrases[%d]" % i, p["en"]) for i, p in enumerate(d["phrases"])]
    out += [("glossary[%d]" % i, g["en"]) for i, g in enumerate(d.get("glossary", []))]
    return out


@pytest.mark.parametrize("name", NAMES)
def test_text_is_clean(name):
    for where, t in _texts(PACKS[name]):
        assert t == t.strip() and "  " not in t and "\n" not in t and "\t" not in t, (name, where, t)
        assert unicodedata.normalize("NFC", t) == t, (name, where)
        assert not re.search(r"\s[,.;:?!]|[,;:?!][A-Za-zÄÖÜäöü]|[a-z]\.[A-Z]", t), (name, where, t)
        assert t.count("(") == t.count(")") and t.count("„") == t.count("“") and t.count('"') % 2 == 0, (name, where, t)


@pytest.mark.parametrize("name", NAMES)
def test_thai_form(name):
    d = PACKS[name]
    items = [("names.th", d["names"]["th"])]
    items += [("phrases[%d]" % i, p["th"]) for i, p in enumerate(d["phrases"])]
    items += [("glossary[%d]" % i, g["th"]) for i, g in enumerate(d.get("glossary", []))]
    for where, t in items:
        assert t == t.strip() and "  " not in t, (name, where, t)
        assert THAI.search(t), (name, where, t)
        assert not re.search(r"[A-Za-z]", t.replace("___", "")), (name, where, t)


@pytest.mark.parametrize("name", NAMES)
def test_english_sentences(name):
    for i, p in enumerate(PACKS[name]["phrases"]):
        en = p["en"]
        where = (name, i, en)
        assert len(en) <= MAX_EN, where
        assert en[-1] in ".?!" or en.endswith(".)"), where
        parts = SENTENCE_END.split(en)
        assert len(parts) <= 2 and ";" not in en, where           # nicht zwei Aussagen in einem Satz
        for s in parts:
            if QUESTION_OPENER.match(s) and not NOT_A_QUESTION.match(s):
                assert s.endswith("?"), where
        assert not US_SPELLING.search(en), where                  # einheitlich britisches Englisch


@pytest.mark.parametrize("name", NAMES)
def test_us_spelling_absent_elsewhere(name):
    d = PACKS[name]
    items = [("note.en", d["note"]["en"])]
    items += [("glossary[%d]" % i, g["en"]) for i, g in enumerate(d.get("glossary", []))]
    for where, t in items:
        if where.startswith("glossary") and t == "trunk":      # Rüssel des Elefanten, kein Kofferraum
            continue
        assert not US_SPELLING.search(t), (name, where, t)


@pytest.mark.parametrize("name", NAMES)
def test_german_is_formal_and_consistent(name):
    d = PACKS[name]
    for key in ("names", "note"):
        assert not INFORMAL_DE.search(d[key]["de"]), (name, key)
    assert "Tourist Police" not in d["note"]["de"], name       # im Deutschen immer „Touristenpolizei“
    assert d["note"]["de"].rstrip()[-1] in ".!?", name


@pytest.mark.parametrize("name", NAMES)
def test_note_marks_machine_translation(name):
    n = PACKS[name]["note"]
    assert n["de"].endswith(MACHINE_DE), name
    assert n["en"].endswith(MACHINE_EN), name
    assert n["de"].count("maschinell") == 1 and n["en"].count("machine-made") == 1, name


@pytest.mark.parametrize("name", NAMES)
def test_critical_marks_are_plausible(name):
    for i, p in enumerate(PACKS[name]["phrases"]):
        where = (name, i, p["en"])
        if EMERGENCY.search(p["en"]):
            assert p.get("critical") is True, where              # Notfallsatz ohne critical
        if p.get("critical"):
            assert not NOT_CRITICAL.search(p["en"]), where       # critical nur für Sicherheit und Notlagen


def test_same_english_sentence_has_same_critical_flag():
    flags = {}
    for name, d in PACKS.items():
        for p in d["phrases"]:
            flags.setdefault(p["en"].strip().lower(), {}).setdefault(bool(p.get("critical")), []).append(name)
    assert {k: v for k, v in flags.items() if len(v) > 1} == {}


def test_same_english_sentence_has_same_thai():
    """Konsistenz „gleicher englischer Satz = gleiches Thai“ über alle Pakete (check_presets, auch Warnungen)."""
    assert check_presets.run([(n + ".json", d) for n, d in PACKS.items()]) == []


@pytest.mark.parametrize("name", NAMES)
def test_glossary_has_no_duplicates(name):
    gl = PACKS[name].get("glossary", [])
    for lang in ("en", "th"):
        vals = [g[lang].strip().lower() for g in gl]
        assert len(vals) == len(set(vals)), (name, lang)


@pytest.mark.parametrize("name", NAMES)
def test_emergency_numbers_are_the_thai_ones(name):
    d = PACKS[name]
    texts = [d["note"]["de"], d["note"]["en"]] + [p["en"] for p in d["phrases"]]
    for t in texts:
        for m in re.finditer(r"(?<![\d.,])(191|199|1669|1155)(?![\d.,])", t):
            before = t[max(0, m.start() - 30):m.start()]
            after = t[m.end():m.end() + 30]
            tourist = re.search(r"tourist", before, re.I) or re.search(r"^\W*(\(|\s)?(tourist|touristen)", after, re.I)
            if m.group(1) == "191":
                assert not tourist, (name, t)                    # 191 ist die Polizei, nicht die Touristenpolizei
            assert re.search(NUMBER_LABELS[m.group(1)], before + " " + after, re.I), (name, m.group(1), t)
        stripped = UNIT.sub(" ", re.sub(r"\d{1,2}\.(–\d{1,2}\.)? (April|Mai)|\d+ ?(a\.m\.|Uhr)", " ", t))
        for m in re.finditer(r"(?<![\d.,–-])(\d{3,4})(?![\d.,])", stripped):
            assert m.group(1) in NUMBER_LABELS, (name, "unbekannte Nummer", m.group(1), t)


@pytest.mark.parametrize("name", NAMES)
def test_emergency_sentences_name_the_right_service(name):
    for p in PACKS[name]["phrases"]:
        en = p["en"]
        for num, label in (("1669", "ambulance"), ("1155", "tourist police"), ("191", "the police")):
            if "(%s)" % num in en:
                assert label in en.lower() and (num in p["th"]), (name, en)
