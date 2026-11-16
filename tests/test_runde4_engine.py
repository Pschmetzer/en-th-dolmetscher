"""Runde 4 (Ideenliste), Engine: Fixes je Nummer, ohne Modelle."""
import types

import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def _fake_claude(monkeypatch, seen, text="ok"):
    r = types.SimpleNamespace(usage=None, stop_reason="end_turn", content=[types.SimpleNamespace(type="text", text=text)])

    def create(**kw):
        seen.append(kw)
        return r
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=types.SimpleNamespace(create=create)))


# --- 44: keine temperature ----------------------------------------------------------------------------------

@pytest.mark.parametrize("model", ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"])
def test_claude_ohne_sampling_parameter(monkeypatch, model):
    """Nr. 44 bewusst NICHT umgesetzt: laut Anthropic-Doku lehnt Claude Opus 5.5 temperature/top_p/top_k ab
    (400), Sonnet 5.5 und Haiku 5.5 lehnen von der Vorgabe abweichende Werte ab (400), und ab API-Version
    2026-10-21 gilt das für alle Modelle. Die Engine darf sie also nie senden."""
    seen = []
    _fake_claude(monkeypatch, seen)
    monkeypatch.setitem(d.LLM, "model", model)
    d.claude_translate("hello", "en", "th")
    assert seen and not {"temperature", "top_p", "top_k"} & set(seen[-1])
