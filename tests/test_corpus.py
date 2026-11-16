"""Gemeinsamer Testkorpus (tests/corpus/*.json, IDEEN 973): Satz + erwartete Übersetzung je Sprachpaar.
Geprüft wird die Text-Logik der Engine, nicht die Übersetzung selbst: Zahlenvergleich (numbers_differ),
Schrift-Plausibilität (_untranslated, _wrong_script, script_share) und Normalisierung des Cache-Schlüssels
(_norm). Gute Fälle dürfen keine Meldung auslösen, schlechte genau die erwartete."""
import importlib.util
import json
import pathlib

import pytest

import dolmetscher as d

CORPUS = pathlib.Path(__file__).resolve().parent / "corpus"
FILES = sorted(CORPUS.glob("*.json"))
CHECKS = ("numbers_differ", "untranslated", "wrong_script")


def _load_make_audio():
    spec = importlib.util.spec_from_file_location("corpus_make_audio", CORPUS / "make_audio.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CASES = _load_make_audio().load_cases()


@pytest.fixture
def pair():
    """Sprachpaar je Fall setzen (Thai-Sonderlogik wie 555-Lachen hängt am Paar) und danach zurück."""
    old = list(d.PAIR)

    def use(src, dst):
        assert d.set_pair(src, dst), (src, dst)
    yield use
    d.set_pair(*old)


def test_korpus_vollstaendig_und_eindeutig():
    assert len(FILES) >= 3 and len(CASES) >= 30
    ids = [c["id"] for c in CASES]
    assert len(ids) == len(set(ids)), "doppelte IDs im Korpus"
    for c in CASES:
        assert c["src"] in d.LANGS and c["dst"] in d.LANGS and c["src"] != c["dst"], c["id"]
        assert c["text"].strip() and c["translation"].strip(), c["id"]
        assert set(c.get("expect", {})) <= set(CHECKS), c["id"]
    pairs = {frozenset((c["src"], c["dst"])) for c in CASES}
    assert {frozenset(("en", "th")), frozenset(("en", "de"))} <= pairs and len(pairs) >= 5
    assert any(c.get("expect") for c in CASES) and sum(not c.get("expect") for c in CASES) >= 20


@pytest.mark.parametrize("case", CASES, ids=[c["id"] for c in CASES])
def test_korpus_pruefungen(case, pair):
    src, dst, text, out = case["src"], case["dst"], case["text"], case["translation"]
    pair(src, dst)
    want = {k: bool(case.get("expect", {}).get(k)) for k in CHECKS}
    got = {"numbers_differ": d.numbers_differ(text, out),
           "untranslated": d._untranslated(text, out, src, dst),
           "wrong_script": d._wrong_script(out, src, dst)}
    assert got == want
    # Gegenrichtung: ein Zahlenfehler fällt in beiden Richtungen auf (Gegenprobe Claude <-> Google)
    assert d.numbers_differ(out, text) == want["numbers_differ"]


@pytest.mark.parametrize("case", [c for c in CASES if not c.get("expect")],
                         ids=[c["id"] for c in CASES if not c.get("expect")])
def test_korpus_gute_uebersetzung_in_zielschrift(case):
    """Gute Übersetzungen bestehen überwiegend aus Buchstaben der Zielschrift (Grundlage der Plausibilität)."""
    assert d.script_share(case["translation"], case["dst"]) >= 0.6
    if d.scripts_distinct(case["src"], case["dst"]):
        assert d.script_share(case["text"], case["src"]) >= 0.6
        assert d.script_share(case["translation"], case["src"]) <= 0.4


def _norm_groups(kind):
    out = []
    for f in FILES:
        for g in json.loads(f.read_text(encoding="utf-8")).get("norm", {}).get(kind, []):
            out.append(pytest.param(g, id=f"{f.stem}:{g[0]}"))
    return out


@pytest.mark.parametrize("group", _norm_groups("same"))
def test_korpus_normalisierung_gleich(group):
    """Schreibvarianten (Groß/klein, Leerraum, Satzende-Punkt, Vollbreiten-？) ergeben denselben Cache-Schlüssel."""
    assert len({d._norm(s) for s in group}) == 1, [d._norm(s) for s in group]


@pytest.mark.parametrize("group", _norm_groups("different"))
def test_korpus_normalisierung_verschieden(group):
    """Frage ≠ Aussage, 1.5 ≠ 15: diese Unterschiede dürfen nicht wegnormalisiert werden."""
    assert len({d._norm(s) for s in group}) == len(group), [d._norm(s) for s in group]


def test_make_audio_say_aufruf(tmp_path):
    cmd = _load_make_audio().say_cmd("Kanya", "-5 องศา", tmp_path / "a.wav")
    assert cmd[:3] == ["say", "-v", "Kanya"] and cmd[-2:] == ["--", "-5 องศา"]
    assert "--data-format=LEI16@16000" in cmd and "--file-format=WAVE" in cmd
