"""Python-Backend Runde 21, Welle 1: robuste Steuerzeilen, history_days, llm_retry."""
import json
import threading

import pytest

import dolmetscher as d


def _run_control(lines, monkeypatch):
    monkeypatch.setattr(d, "_stdin_lines", lambda: iter(lines))
    monkeypatch.setattr(d, "STOP", threading.Event())
    seen = []
    monkeypatch.setattr(d, "apply_control", lambda eng, dd: seen.append(dd))
    d.control_loop(object(), jobs=None)
    d.STOP.wait(3)
    return seen


def test_tief_verschachteltes_json_beendet_steuerung_nicht(monkeypatch):
    lines = ["[" * 100000 + "\n", json.dumps({"ping": 1}) + "\n"]
    seen = _run_control(lines, monkeypatch)
    assert seen == [{"ping": 1}]            # RecursionError übersprungen, nächste Zeile verarbeitet


def test_history_days_bool_ist_ungueltig(monkeypatch):
    import history_store
    rec = history_store.RECORDER
    monkeypatch.setattr(rec, "keep_days", 30.0)
    events = []
    monkeypatch.setattr(d, "emit", lambda kind, **kw: events.append((kind, kw)))
    d.history_set_days(False)
    assert rec.keep_days == 30.0
    assert events and events[0][1]["code"] == "history_days_invalid"


def test_llm_retry_false_text_laedt_nicht_neu(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "llm_reload", lambda: calls.append(1))
    eng = type("E", (), {})()
    d.apply_control(eng, {"llm_retry": "false"})
    assert calls == []
    d.apply_control(eng, {"llm_retry": True})
    assert calls == [1]
