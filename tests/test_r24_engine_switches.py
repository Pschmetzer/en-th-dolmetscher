"""Runde 24: bisher nur im Code liegende Schalter als Steuerfelder/Umgebungsvariable, Fähigkeiten, Fehlertexte."""
import collections
import re
import types

import pytest

import dolmetscher as d

_REAL_EMIT = d.emit


def _eng():
    e = types.SimpleNamespace(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False,
                              paused=False, rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False)
    e.stop_speaking = lambda: None
    return e


@pytest.fixture(autouse=True)
def _restore(monkeypatch):
    for tab, key in ((d.LLM, "stream"), (d.LLM, "router"), (d.DEFER, "on"), (d.PARALLEL_ALT, "on"),
                     (d.STT_PROMPT, "on"), (d.SPEAK_NUMBER_WORDS, "on")):
        monkeypatch.setitem(tab, key, False)
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)


SWITCHES = [("llm_stream", d.LLM, "stream"), ("llm_router", d.LLM, "router"), ("defer", d.DEFER, "on"),
            ("parallel_alt", d.PARALLEL_ALT, "on"), ("stt_prompt", d.STT_PROMPT, "on"),
            ("speak_numbers", d.SPEAK_NUMBER_WORDS, "on")]


@pytest.mark.parametrize("field,tab,key", SWITCHES)
def test_control_field_switches_on_and_off(field, tab, key):
    assert field in d.CTRL_KEYS and field in d.CTRL_LOG_KEYS
    d.apply_control(_eng(), {field: True})
    assert tab[key] is True
    d.apply_control(_eng(), {field: "false"})            # Text wie bei den übrigen bool-Feldern
    assert tab[key] is False


@pytest.mark.parametrize("field,tab,key", SWITCHES)
def test_control_field_invalid_value_changes_nothing(field, tab, key):
    d.apply_control(_eng(), {field: [1]})
    assert tab[key] is False


def test_unknown_switch_values_are_not_reported_as_unknown_keys(monkeypatch):
    seen = []
    monkeypatch.setattr(d, "emit", lambda ev, **kw: seen.append(ev))
    d.apply_control(_eng(), {"llm_stream": True, "defer": True})
    assert "control_ignored" not in seen


def test_features_env_turns_switches_on():
    on = d.apply_features("stream, router;defer parallel_alt,stt_prompt,speak_numbers")
    assert on == list(d.FEATURES)
    assert d.LLM["stream"] and d.LLM["router"] and d.DEFER["on"] and d.PARALLEL_ALT["on"]
    assert d.STT_PROMPT["on"] and d.SPEAK_NUMBER_WORDS["on"]


def test_features_env_unknown_name_ignored_and_empty_is_noop():
    assert d.apply_features("nonsense,STREAM") == ["stream"]
    assert d.apply_features("") == [] and d.apply_features(None) == []


def test_speak_numbers_changes_thai_output_only_when_on():
    assert "350" in d.speak_form("ราคา 350 บาท", "th")
    d.apply_control(_eng(), {"speak_numbers": True})
    assert "350" not in d.speak_form("ราคา 350 บาท", "th")


def test_stt_prompt_follows_switch(monkeypatch):
    monkeypatch.setattr(d, "ENTITIES", collections.OrderedDict(Somchai=True))
    assert d.stt_prompt("en") == ""
    d.apply_control(_eng(), {"stt_prompt": True})
    assert "Somchai" in d.stt_prompt("en")


def test_capabilities_list_controls_and_features():
    caps = d.capabilities()
    assert caps == sorted(caps) and len(caps) == len(set(caps))
    for k in ("llm_stream", "llm_router", "defer", "parallel_alt", "stt_prompt", "speak_numbers", "say", "beam"):
        assert f"control:{k}" in caps
    assert "feature:trace" in caps and "feature:mps_fallback" in caps


def test_ready_event_carries_capabilities():
    src = open(d.__file__, encoding="utf-8").read()
    assert "capabilities=capabilities()" in src


def test_state_snapshot_reports_switches_and_latency_history(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda event, **kw: ev.append((event, kw)))
    monkeypatch.setattr(d, "llm_available", lambda: False)
    monkeypatch.setattr(d, "_history_on", lambda: False)
    d.apply_control(_eng(), {"defer": True, "llm_stream": True})
    stub = types.SimpleNamespace(state_fields=lambda: {}, mute=False, earcons=False, beam=1, two_person=True)
    d.Engine.emit_snapshot(stub)
    kw = ev[-1][1]
    assert ev[-1][0] == "state" and kw["switches"]["defer"] is True and kw["switches"]["llm_stream"] is True
    assert kw["switches"]["llm_router"] is False and "latency_hist" in kw


def test_every_emitted_error_code_has_english_text():
    src = open(d.__file__, encoding="utf-8").read()
    codes = set(re.findall(r'emit\("error",\s*code="([a-z_]+)"', src))
    codes |= set(re.findall(r'return "(mic_[a-z]+)", ', src))
    codes |= {"mic_failed"}
    missing = sorted(c for c in codes if c not in d.ERROR_EN)
    assert not missing, missing


def test_error_event_gets_msg_en_but_keeps_explicit_one(monkeypatch):
    lines = []
    monkeypatch.setattr(d, "_emit", lambda ev, **kw: lines.append((ev, kw)))
    _REAL_EMIT("error", code="mic_invalid", msg="Mikrofon-Angabe ungültig")
    _REAL_EMIT("error", code="mic_invalid", msg="x", msg_en="custom")
    _REAL_EMIT("error", code="unbekannt_xyz", msg="y")
    assert lines[0][1]["msg_en"] == d.ERROR_EN["mic_invalid"] and lines[0][1]["msg"].startswith("Mikrofon")
    assert lines[1][1]["msg_en"] == "custom"
    assert "msg_en" not in lines[2][1]
