"""Tests für Szenario-Presets – ohne Modell, Netz oder Mikrofon."""
import json
import pathlib

import pytest

import dolmetscher as D
import presets as P

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHIPPED = {"travel", "restaurant", "hotel", "taxi", "doctor", "office", "shopping", "pharmacy", "police", "bank",
           "spa", "temple", "rental", "scooter", "transport", "lostchild"}


@pytest.fixture(autouse=True)
def home(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    return tmp_path


def good(**kw):
    d = {"id": "demo", "names": {"de": "Demo", "en": "Demo", "th": "เดโม"}, "style": "polite",
         "glossary": [{"en": "room", "th": "ห้อง"}], "phrases": [{"en": "Hello", "th": "สวัสดี"}]}
    d.update(kw)
    return d


def test_shipped_presets_valid():
    allp = P.load_all()
    assert SHIPPED <= set(allp), P.last_errors
    assert not P.last_errors
    for p in allp.values():
        assert p["phrases"] and p["glossary"]
        assert all("ครับ" not in x["th"] and "ค่ะ" not in x["th"] for x in p["phrases"])   # geschlechtsneutral


@pytest.mark.parametrize("patch", [
    {"id": "Bad Id"}, {"id": ""}, {"style": "rude"}, {"names": {"de": "x", "en": "x"}},
    {"names": {"de": "x" * 41, "en": "x", "th": "x"}}, {"polite": "maybe"}, {"voice": {"fr": "x"}},
    {"glossary": [{"en": "a"}]}, {"glossary": [{"en": "a" * 61, "th": "b"}]},
    {"phrases": [{"en": "a", "th": "b" * 201}]}, {"phrases": [{"en": "a", "th": "b"}] * 51},
    {"extra": 1}, {"glossary": "x"},
])
def test_validate_rejects(patch):
    assert P.validate(good(**patch))


def test_validate_accepts_and_non_dict():
    assert P.validate(good(polite="ka", voice={"th": "th-TH-PremwadeeNeural"})) == []
    assert P.validate([]) and P.validate(None)


def test_user_dir_overrides_and_skips_broken(home):
    ud = home / "presets"
    ud.mkdir()
    (ud / "hotel.json").write_text(json.dumps(good(id="hotel", style="casual")), encoding="utf-8")
    (ud / "mine.json").write_text(json.dumps(good(id="mine")), encoding="utf-8")
    (ud / "kaputt.json").write_text("{nope", encoding="utf-8")
    (ud / "falsch.json").write_text(json.dumps(good(style="x")), encoding="utf-8")
    allp = P.load_all()
    assert allp["hotel"]["style"] == "casual" and "mine" in allp and "taxi" in allp
    assert len(P.last_errors) == 2


class FakeEng:
    def __init__(self): self.polite, self.voices = "krub", {"en": None, "th": None}


def test_activate_and_restore():
    allp = P.load_all()
    gl = [("Pim", None), ("room", "Zimmer")]
    llm, eng, st = {"style": "casual"}, FakeEng(), P.PresetState()
    st.activate("hotel", allp, gl, llm, eng)
    assert llm["style"] == "polite" and ("check-in", "เช็คอิน") in gl and ("เช็คอิน", "check-in") in gl
    assert ("room", "Zimmer") in gl and ("room", "ห้อง") not in gl       # eigener Eintrag gewinnt
    st.activate("taxi", allp, gl, llm, eng)                                # Wechsel: kein Hotel-Rest
    assert ("check-in", "เช็คอิน") not in gl and ("meter", "มิเตอร์") in gl
    st.activate(None, allp, gl, llm, eng)
    assert gl == [("Pim", None), ("room", "Zimmer")] and llm["style"] == "casual" and st.active is None
    with pytest.raises(KeyError):
        st.activate("gibtsnicht", allp, gl, llm, eng)
    assert gl == [("Pim", None), ("room", "Zimmer")]


def test_activate_voice_polite_restored():
    allp = {"d": good(id="d", polite="ka", voice={"th": "th-TH-PremwadeeNeural"})}
    eng, st = FakeEng(), P.PresetState()
    st.activate("d", allp, [], {"style": "neutral"}, eng)
    assert eng.polite == "ka" and eng.voices["th"] == "th-TH-PremwadeeNeural"
    st.activate("none", allp, [], {"style": "neutral"}, eng)
    assert eng.polite == "krub" and eng.voices["th"] is None


@pytest.mark.parametrize("text, key", [
    ("hotel mode", "preset:hotel"), ("Hotel mode.", "preset:hotel"), ("preset taxi", "preset:taxi"),
    ("restaurant mode", "preset:restaurant"), ("doctor mode", "preset:doctor"),
    ("preset off", "preset:none"), ("preset none", "preset:none"),
])
def test_voice_command(text, key):
    assert D.parse_command(text) == key


@pytest.mark.parametrize("text", [
    "preset", "hotel", "mode", "preset unknown", "banana mode",
    "i would like to go to the hotel mode of operation", "please set the preset to hotel mode now",
    "thai only", "english mode", "pause",
])
def test_voice_command_negative(text):
    assert not (D.parse_command(text) or "").startswith("preset:")


def test_existing_commands_unchanged():
    assert D.parse_command("Thai only") == "thai" and D.parse_command("pause") == "pause"


def test_apply_control_preset_and_event(capsys, monkeypatch):
    monkeypatch.setattr(D, "JSON", True)
    eng = FakeEng()
    eng.translate_dir = {"en": True, "th": True}
    monkeypatch.setattr(D, "GLOSSARY", [("Pim", None)])
    monkeypatch.setattr(D, "PRESET", P.PresetState())
    monkeypatch.setitem(D.LLM, "style", "casual")
    D.apply_control(eng, {"preset": "hotel"})
    out = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert {k: out[k] for k in ("event", "id", "name")} == {"event": "preset", "id": "hotel", "name": "Hotel"}
    assert out["phrases"] and all(set(ph) == {"en", "th", "critical"} for ph in out["phrases"])   # Runde 5
    assert D.LLM["style"] == "polite" and any(a == "check-in" for a, _ in D.GLOSSARY)
    D.apply_control(eng, {"style": "neutral"})            # Nutzeränderung wird Basis, Preset bleibt aktiv
    assert D.PRESET.active == "hotel"
    D.apply_control(eng, {"preset": "none"})
    out = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert out == {"event": "preset", "id": None, "name": None, "note": None, "phrases": []}
    assert D.LLM["style"] == "neutral" and D.GLOSSARY == [("Pim", None)]
    D.apply_control(eng, {"preset": "nope"})              # unbekannt: nichts ändern, kein Event
    assert D.PRESET.active is None
