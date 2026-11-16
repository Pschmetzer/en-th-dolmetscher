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
    r = types.SimpleNamespace(usage=None, stop_reason="end_turn",
                              content=[types.SimpleNamespace(type="text", text=text)])

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


# --- 28/165: Offline-Übersetzung über translate-helper ---------------------------------------------------

FAKE_HELPER = r'''#!{py}
import json, sys, time
print(json.dumps({{"ready": True, "pairs": {{"en-th": "installed", "th-en": "supported"}}}}), flush=True)
for line in sys.stdin:
    r = json.loads(line)
    if r["text"] == "hang":
        time.sleep(30)
    print(json.dumps({{"id": r["id"], "out": "OFF:" + r["text"], "ms": 5}}), flush=True)
'''


@pytest.fixture
def helper(tmp_path, monkeypatch):
    import sys
    f = tmp_path / "translate-helper"
    f.write_text(FAKE_HELPER.format(py=sys.executable))
    f.chmod(0o755)
    mt = d.OfflineMT()
    monkeypatch.setattr(d, "OFFLINE_MT", mt)
    yield mt, str(f)
    mt.close()


def _offline(monkeypatch):
    import urllib.error

    def boom(*a, **k):
        raise urllib.error.URLError(OSError("no route"))
    monkeypatch.setattr(d, "google_translate", boom)
    monkeypatch.setattr(d, "mymemory_translate", boom)


def test_offline_mt_springt_nur_ohne_netz_ein(helper, monkeypatch):
    mt, path = helper
    assert mt.configure(path, on=True)
    _offline(monkeypatch)
    meta = {}
    assert d.translate("Where is the station?", "en", "th", meta=meta) == "OFF:Where is the station?"
    assert meta["provider"] == "apple"
    assert d._cache_get(d._cache_key("Where is the station?", "en", "th", False, "krub")) is None   # nicht gecacht


def test_offline_mt_nicht_bei_erreichbarem_anbieter(helper, monkeypatch):
    mt, path = helper
    mt.configure(path, on=True)
    monkeypatch.setattr(d, "google_translate", lambda *a, **k: "สวัสดี")
    meta = {}
    assert d.translate("Hello there friend", "en", "th", meta=meta) == "สวัสดี" and meta["provider"] == "google"
    assert mt.proc is None                     # Helfer gar nicht gestartet


def test_offline_mt_nur_installiertes_paar(helper, monkeypatch):
    mt, path = helper
    mt.configure(path, on=True)
    assert mt.translate("สวัสดี", "th", "en") is None        # th-en nur "supported"
    assert mt.translate("hi", "en", "th") == "OFF:hi"


def test_offline_mt_aus_ohne_optin_und_ohne_helfer(helper, monkeypatch):
    mt, path = helper
    assert not mt.configure(path, on=False) and mt.translate("hi", "en", "th") is None
    monkeypatch.delenv("DOLMETSCHER_TRANSLATE_HELPER", raising=False)
    assert not mt.configure("/nicht/da", on=True)


def test_offline_mt_zeitgrenze(helper, monkeypatch):
    mt, path = helper
    mt.configure(path, on=True)
    monkeypatch.setattr(d, "OFFLINE_MT_TIMEOUT", 0.3)
    t = d.time.monotonic()
    assert mt.translate("hang", "en", "th") is None
    assert d.time.monotonic() - t < 3 and mt.proc is None   # hängender Helfer wird beendet
