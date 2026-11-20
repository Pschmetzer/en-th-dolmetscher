"""Runde 21 (py1) Welle 2: Log-Meldung, Aussprache-Cache, Fragewörter, Währungen, Platzprüfung, Google-POST-Größe."""
import errno

import pytest

import dolmetscher as d


@pytest.fixture(autouse=True)
def _reset():
    old = list(d.PRONOUNCE)
    yield
    d.PRONOUNCE[:] = old


def test_pronounce_cache_follows_changes():
    d.PRONOUNCE[:] = [("Pat", "Pät")]
    assert d.apply_pronounce("Hi Pat, pattern") == "Hi Pät, pattern"
    d.PRONOUNCE[:] = [("Pat", "Paht")]
    assert d.apply_pronounce("Hi Pat") == "Hi Paht"
    d.PRONOUNCE[:] = []
    assert d.apply_pronounce("Hi Pat") == "Hi Pat"


@pytest.mark.parametrize("lang,text,expected", [
    ("it", "Dove è la stazione", True), ("it", "Che bello", False),
    ("pt", "Onde fica o banheiro", True), ("nl", "Waar is het station", True),
    ("ru", "Где вокзал", True), ("ru", "Хорошо", False), ("nl", "Prima", False),
])
def test_question_words_more_languages(lang, text, expected):
    assert d.is_question(text, lang) is expected


@pytest.mark.parametrize("text", ["Es tut mir leid, ich kann das nicht übersetzen.", "Lo siento, no puedo traducir eso",
                                  "ขออภัย ฉันไม่สามารถแปลได้"])
def test_refusals_other_languages(text):
    assert d._LLM_REFUSAL.search(text)


def test_refusal_normal_sentence_ok():
    assert not d._LLM_REFUSAL.search("Es tut mir leid, dass es regnet")


def test_more_currencies_detected():
    assert d.currency_amounts("500 yuan") == [("CNY", 500)] or d.currency_amounts("500 yuan")[0][0] == "CNY"
    assert d.currency_amounts("₩5000")[0][0] == "KRW"
    assert d.currency_amounts("₹200")[0][0] == "INR"
    assert d.currency_amounts("50 ringgit")[0][0] == "MYR"
    assert d.currency_mismatch("500 yuan", "500 baht")
    assert not d.currency_mismatch("500 yuan", "500 หยวน")
    assert not d.currency_amounts("we won 5 games")


def test_disk_check(tmp_path):
    assert d.enough_disk_for("small", str(tmp_path))
    assert d.enough_disk_for("small", str(tmp_path / "gibt-es-nicht" / "x"))
    assert d.enough_disk_for("small", "/nonexistent-root-xyz/abc") in (True, False)


def test_wm_disk_full(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda ev, **kw: events.append((ev, kw)))
    monkeypatch.setattr(d, "enough_disk_for", lambda m, path=None: False)

    class W:
        def __init__(self, *a, **k):
            if k.get("local_files_only"):
                raise FileNotFoundError("not found in cache")
            raise AssertionError("darf nicht laden")
    monkeypatch.setattr(d, "_whisper_cls", lambda: W)
    d._DOWNLOAD_SAID.clear()
    with pytest.raises(OSError) as ei:
        d._wm("small")
    assert ei.value.errno == errno.ENOSPC
    assert any(k.get("code") == "disk_full" for _, k in events)


def test_google_uses_bigger_pieces_with_post(monkeypatch):
    seen = []
    monkeypatch.setattr(d, "_google_pieces", lambda pieces, s, t: seen.append(pieces) or ["x"] * len(pieces))
    d.HTTP.no_post.clear()
    d.google_translate("hello. " * 150, "en", "de")      # ~1000 Byte
    assert len(seen[-1]) == 1
    d.HTTP.no_post["translate.googleapis.com"] = 1e18
    try:
        d.google_translate("hello. " * 150, "en", "de")
        assert len(seen[-1]) > 1
    finally:
        d.HTTP.no_post.clear()


def test_log_unavailable_once(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda ev, **kw: events.append((ev, kw)))
    monkeypatch.setattr(d, "_logger", lambda: (_ for _ in ()).throw(OSError("voll")))
    monkeypatch.setitem(d._LOG_FAIL, "told", False)
    d.log({"a": 1})
    d.log({"a": 2})
    assert len(events) == 1 and events[0][1]["code"] == "log_unavailable"


def test_history_error_rate_limited(monkeypatch):
    import history_store
    logs = []
    monkeypatch.setattr(d, "log", lambda x: logs.append(x))

    class R:
        def utt(self, kw):
            raise RuntimeError("db kaputt")
    monkeypatch.setattr(history_store, "RECORDER", R())
    monkeypatch.setitem(d._HIST_FAIL, "n", 0)
    for _ in range(60):
        d._record("utt", {})
    assert len(logs) == 2


def test_claude_long_text_gets_more_tokens_and_stop_sequence_ok(monkeypatch):
    import types
    sent = []

    class Msgs:
        def create(self, **kw):
            sent.append(kw)
            return types.SimpleNamespace(stop_reason="stop_sequence",
                                         content=[types.SimpleNamespace(type="text", text="ok")])
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    assert d.claude_translate("word " * 400, "en", "de") == "ok"
    assert sent[0]["max_tokens"] > 512
    d.claude_translate("hi", "en", "de")
    assert sent[1]["max_tokens"] == 512


def test_child_stderr_truncates_big_file(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "LOGFILE", str(tmp_path / "engine.log"))
    monkeypatch.setattr(d, "DEBUG", True)
    monkeypatch.setattr(d, "FFLOG_MAX", 10)
    monkeypatch.setitem(d._FFLOG, "f", None)
    f = tmp_path / "engine.log.ffmpeg"
    f.write_bytes(b"x" * 100)
    h = d._child_stderr()
    try:
        assert f.stat().st_size == 0
    finally:
        h.close()
