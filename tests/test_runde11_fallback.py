"""Runde 11: Robustheit der Übersetzungs-Fallbacks (Claude → Google → MyMemory → Offline)."""
import types
import urllib.parse

import pytest

import dolmetscher as d


def _claude(monkeypatch, stop_reason="end_turn", text="สวัสดี"):
    class Msgs:
        def create(self, **kw):
            blocks = [types.SimpleNamespace(type="text", text=text)] if text is not None else []
            return types.SimpleNamespace(stop_reason=stop_reason, usage=None, content=blocks)
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))


# --- Google: sehr lange Sätze sprengen die URL (HTTP 414) -------------------------------------------------------

def test_google_long_thai_sentence_is_sent_in_short_requests(monkeypatch):
    urls = []

    def gj(u, t=0):
        urls.append(u)
        return [[["part", "x"]]]
    monkeypatch.setattr(d, "_get_json", gj)
    text = ("สวัสดีครับวันนี้อากาศดีมากเลย " * 40).strip()
    out = d.google_translate(text, "th", "en")
    assert len(urls) > 1 and max(len(u) for u in urls) < 2000
    assert out.count("part") == len(urls)
    # alle Teile zusammen ergeben wieder den ganzen Text
    got = "".join(urllib.parse.unquote(u.split("&q=")[1]) for u in urls)
    assert got.replace(" ", "") == text.replace(" ", "")


def test_google_short_sentence_is_one_request(monkeypatch):
    urls = []
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: urls.append(u) or [[["Good night", "x"]]])
    assert d.google_translate("Gute Nacht", "de", "en") == "Good night" and len(urls) == 1


def test_google_chunk_failure_fails_whole_sentence(monkeypatch):
    calls = []

    def gj(u, t=0):
        calls.append(u)
        if len(calls) == 2:
            raise OSError("verbindung weg")
        return [[["a", "x"]]]
    monkeypatch.setattr(d, "_get_json", gj)
    with pytest.raises(OSError):
        d.google_translate("Wort " * 300, "de", "en")


# --- Anbieter gibt die Eingabe unverändert zurück (gleiche Schrift) ---------------------------------------------

def test_google_echo_in_same_script_is_rejected(monkeypatch):
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: [[["Where is the train station today", "x"]]])
    with pytest.raises(ValueError):
        d.google_translate("Where is the train station today", "en", "de")


def test_google_echo_of_a_name_is_still_fine(monkeypatch):
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: [[["Hotel California", "x"]]])
    assert d.google_translate("Hotel California", "en", "de") == "Hotel California"


def test_mymemory_echo_is_rejected(monkeypatch):
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: {
        "responseStatus": 200, "responseData": {"translatedText": "Where is the train station today",
                                                 "match": 1}})
    with pytest.raises(RuntimeError):
        d.mymemory_translate("Where is the train station today", "en", "de")


def test_mymemory_untranslated_for_thai_is_rejected(monkeypatch):
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: {
        "responseStatus": 200, "responseData": {"translatedText": "Hello there my friend", "match": 1}})
    with pytest.raises(RuntimeError):
        d.mymemory_translate("Hello there my friend", "en", "th")


def test_mymemory_wrong_script_is_rejected(monkeypatch):
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: {
        "responseStatus": 200, "responseData": {"translatedText": "สวัสดีครับ", "match": 1}})
    with pytest.raises(RuntimeError):
        d.mymemory_translate("สวัสดีครับ", "th", "en")


def test_echoing_google_falls_through_to_mymemory(monkeypatch):
    def gj(u, t=0):
        if "translate.googleapis" in u:
            return [[["Where is the train station today", "x"]]]
        return {"responseStatus": 200, "responseData": {"translatedText": "Wo ist heute der Bahnhof", "match": 1}}
    monkeypatch.setattr(d, "_get_json", gj)
    meta = {}
    assert d._mt_chain("Where is the train station today", "en", "de", meta) == "Wo ist heute der Bahnhof"
    assert meta["provider"] == "mymemory"


# --- Claude: halbe/leere Antwort ist kein Ausfall --------------------------------------------------------------

@pytest.mark.parametrize("kw", [dict(stop_reason="max_tokens", text="halb"), dict(text=None),
                                dict(stop_reason="refusal", text="")])
def test_bad_claude_answer_does_not_pause_claude(monkeypatch, kw):
    _claude(monkeypatch, **kw)
    with pytest.raises(RuntimeError) as ei:
        d.claude_translate("x", "en", "th")
    assert d._llm_backoff(ei.value) == 0.0


def test_claude_still_backs_off_after_real_outage():
    assert d._llm_backoff(RuntimeError("boom")) == d.LLM_BACKOFF
