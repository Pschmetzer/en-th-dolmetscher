"""Runde 21 (py1) Welle 3: Gegenprobe ersetzt den Cache, robustes Preset-Tuning, Gruß-Stoppwörter."""
import pytest

import dolmetscher as d


@pytest.fixture(autouse=True)
def _clean():
    d._cache_clear()
    yield
    d._cache_clear()


def test_recheck_replaces_cached_wrong_numbers(monkeypatch):
    monkeypatch.setitem(d.LLM, "on", False)
    key = d._cache_key("Das kostet 500 Baht", "de", "th", False, "krub")
    d._cache_put(key, ("ราคา 300 บาท", "google"))
    monkeypatch.setattr(d, "_mt_chain", lambda *a, **k: "ราคา 500 บาท")
    # erster Anbieter "claude" -> Gegenprobe über Google; Cache beider Schlüssel bekommt die zahlentreue Fassung
    meta = {"provider": "claude"}
    out = d.recheck_numbers("Das kostet 500 Baht", "de", "th", "ราคา 300 บาท", meta)
    assert out == "ราคา 500 บาท"
    assert d._cache_get(key)[0] == "ราคา 500 บาท"


def test_preset_tuning_survives_garbage(monkeypatch):
    class Eng:
        rate = 0
    eng = Eng()
    old = d.SILENCE_END
    try:
        d._TUNING_SAVED.clear()
        d._apply_preset_tuning(eng, {"tuning": {"silence": "kaputt", "let_finish": None, "rate": "x"}})
        assert d.SILENCE_END == old
        d._apply_preset_tuning(eng, {"tuning": {"silence": 99, "rate": 10}})
        assert d.SILENCE_END == 2.0 and eng.rate == 10
        d._apply_preset_tuning(eng, None)
        assert d.SILENCE_END == old and eng.rate == 0
    finally:
        d.SILENCE_END = old
        d._TUNING_SAVED.clear()


def test_greeting_in_other_language_is_not_a_name():
    assert not d._looks_like_name("Guten Morgen")
    assert not d._looks_like_name("Buenos Dias")
    assert d._looks_like_name("Hotel California")


def test_german_greeting_echo_is_rejected():
    assert d._echoed("Guten Morgen wie geht es dir", "Guten Morgen wie geht es dir", "de", "en") is True


def test_glossary_limit_constant(monkeypatch):
    lines = "\n".join(f"w{i} => x{i}" for i in range(d.GLOSSARY_LIMIT + 50))
    monkeypatch.setattr(d, "_write_private", lambda *a, **k: None)
    old = list(d.GLOSSARY)
    try:
        d.load_glossary(lines)
        assert len(d.GLOSSARY) == d.GLOSSARY_LIMIT
    finally:
        d.GLOSSARY[:] = old


def test_restore_accepts_rewritten_placeholder():
    assert d._restore("Hallo (1) und [2]", ["Tony", "Anna"]) == "Hallo Tony und Anna"
    assert d._restore("Hallo", ["Tony"]) is None


def test_protect_roundtrip_unchanged(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Pattaya", "พัทยา"), ("Tony", None)])
    monkeypatch.setattr(d, "_GLOSSARY_OWN", None)
    prot, slots = d._protect("I live in Pattaya with Tony", "th")
    assert slots == ["พัทยา", "Tony"] and "[1]" in prot and "[2]" in prot


def test_llm_client_rebuilt_when_env_key_changes(monkeypatch):
    import sys
    import types
    made = []
    fake = types.SimpleNamespace(Anthropic=lambda **kw: made.append(kw) or object())
    monkeypatch.setitem(sys.modules, "anthropic", fake)
    monkeypatch.setitem(d.LLM, "client", None)
    monkeypatch.delitem(d.LLM, "client_env", raising=False)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "k1")
    c1 = d.llm_client()
    assert d.llm_client() is c1
    monkeypatch.setenv("ANTHROPIC_API_KEY", "k2")
    c2 = d.llm_client()
    assert c2 is not c1 and made[-1]["api_key"] == "k2"
    monkeypatch.setitem(d.LLM, "client", None)


def test_captive_portal_event_has_test_url(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    monkeypatch.setitem(d._CAPTIVE, "t", -1e9)
    d._captive_hint()
    assert ev[0][0] == "captive_portal" and ev[0][1]["url"].startswith("http://")


def test_old_cache_file_dropped(tmp_path, monkeypatch):
    import json
    import os
    f = tmp_path / "cache.json"
    f.write_text(json.dumps([[["a", "en", "de", "mt", ""], ["b", "google"]]]))
    monkeypatch.setattr(d, "CACHE_FILE", str(f))
    old = os.stat(f).st_mtime - d.CACHE_TTL_S - 10
    os.utime(f, (old, old))
    try:
        d.cache_persist(True)
        assert d._cache_get(("a", "en", "de", "mt", "")) is None and not f.exists()
        f.write_text(json.dumps([[["a", "en", "de", "mt", ""], ["b", "google"]]]))
        d.cache_persist(True)
        assert d._cache_get(("a", "en", "de", "mt", "")) == ("b", "google")
    finally:
        d._CACHE_DISK["on"] = False


def test_say_voice_list_refreshes_after_ttl(monkeypatch):
    import subprocess
    import types
    calls = []
    out = types.SimpleNamespace(stdout="Anna de_DE x\n")
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: calls.append(1) or out)
    monkeypatch.setattr(d, "_SAY_LIST", {"out": None, "fail_t": None})
    d._say_voices()
    d._say_voices()
    assert len(calls) == 1
    d._SAY_LIST["t"] -= d.SAY_LIST_TTL + 1
    d._say_voices()
    assert len(calls) == 2
