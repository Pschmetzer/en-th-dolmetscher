"""Runde 21 (py1) Welle 5."""
import queue
import threading
import time

import dolmetscher as d


def test_history_write_does_not_hold_emit_lock(monkeypatch):
    q = queue.Queue(maxsize=50)
    monkeypatch.setattr(d, "JSON", True)
    monkeypatch.setitem(d._OUT, "q", q)
    gate, started = threading.Event(), threading.Event()

    def slow_record(event, kw):
        started.set()
        gate.wait(3)
    monkeypatch.setattr(d, "_record", slow_record)
    t = threading.Thread(target=d.emit, args=("utt",), kwargs=dict(id="u1", text="x"), daemon=True)
    t.start()
    assert started.wait(2)
    t0 = time.monotonic()
    d.emit("level", rms=0.1)                  # darf nicht auf den langsamen Verlauf warten
    assert time.monotonic() - t0 < 1.0
    gate.set()
    t.join(3)
    events = [__import__("json").loads(x)["event"] for x in list(q.queue)]
    assert events == ["level", "utt"]


class _Conn:
    def __init__(self, fail):
        self.fail, self.sock, self.timeout, self.closed = fail, None, 1, False

    def request(self, *a, **k):
        if self.fail:
            raise ConnectionResetError("reset")

    def getresponse(self):
        class R:
            status, reason, headers, will_close = 200, "OK", {}, True

            def read(self, n=-1):
                return b'{"ok": 1}'

            def getheader(self, *_):
                return "application/json"
        return R()

    def close(self):
        self.closed = True


def test_fresh_connection_reset_is_retried_once(monkeypatch):
    ka = d.KeepAlive()
    seq = [_Conn(True), _Conn(False)]
    monkeypatch.setattr(ka, "_new", lambda host, timeout: seq.pop(0))
    assert ka.get_json("https://example.org/x", 2) == {"ok": 1}
    assert not seq


def test_fresh_connection_other_error_not_retried(monkeypatch):
    import urllib.error

    import pytest

    class Boom(_Conn):
        def request(self, *a, **k):
            raise OSError("anderer Fehler")
    ka = d.KeepAlive()
    seq = [Boom(False), _Conn(False)]
    monkeypatch.setattr(ka, "_new", lambda host, timeout: seq.pop(0))
    with pytest.raises(urllib.error.URLError):
        ka.get_json("https://example.org/x", 2)
    assert len(seq) == 1


# ---- _translate: Anbieter-Kombinationen mit Fake-Anbietern (Claude spät, Google Fehler, beide Fehler) ----

import concurrent.futures  # noqa: E402

import pytest  # noqa: E402


class _Fut(concurrent.futures.Future):
    pass


@pytest.fixture
def chain(monkeypatch):
    d._cache_clear()
    d.reset_net_backoff()
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    monkeypatch.setattr(d, "llm_over_budget", lambda: False)
    monkeypatch.setattr(d, "_hedge_s", lambda: 0.05)
    monkeypatch.setattr(d, "_offline_mt", lambda *a, **k: None)
    monkeypatch.setattr(d, "_llm_failed", lambda e: None)
    yield monkeypatch
    d._cache_clear()
    d.reset_net_backoff()


def _claude(result=None, exc=None, delay=0.0):
    def make(*a, **k):
        f = _Fut()

        def run():
            time.sleep(delay)
            f.set_exception(exc) if exc else f.set_result(result)
        threading.Thread(target=run, daemon=True).start()
        return f
    return make


def test_claude_fast_wins(chain):
    chain.setattr(d, "_claude_async", _claude("Hallo"))
    chain.setattr(d, "_mt_chain", lambda *a, **k: pytest.fail("Google nicht nötig"))
    meta = {}
    assert d._translate("Hello", "en", "de", meta=meta) == "Hallo" and meta["provider"] == "claude"


def test_claude_error_falls_back_to_google(chain):
    chain.setattr(d, "_claude_async", _claude(exc=RuntimeError("boom")))

    def mt(text, src, dst, meta, deadline=None):
        meta["provider"] = "google"
        return "Hallo (g)"
    chain.setattr(d, "_mt_chain", mt)
    meta = {}
    assert d._translate("Hello", "en", "de", meta=meta) == "Hallo (g)" and meta["provider"] == "google"
    # Google-Ersatz wird nicht als Claude-Ergebnis gemerkt
    assert d._cache_get(d._cache_key("Hello", "en", "de", True, "krub")) is None
    assert d._cache_get(d._cache_key("Hello", "en", "de", False, "krub"))[0] == "Hallo (g)"


def test_slow_claude_google_fails_waits_for_claude(chain):
    chain.setattr(d, "_claude_async", _claude("Hallo (c)", delay=0.3))

    def mt(*a, **k):
        raise RuntimeError("google down")
    chain.setattr(d, "_mt_chain", mt)
    meta = {}
    assert d._translate("Hello", "en", "de", meta=meta) == "Hallo (c)" and meta["provider"] == "claude"


def test_slow_claude_google_wins_but_claude_done_in_time_is_used(chain):
    chain.setattr(d, "_claude_async", _claude("Hallo (c)", delay=0.12))

    def mt(text, src, dst, meta, deadline=None):
        time.sleep(0.3)                       # Claude ist inzwischen fertig
        meta["provider"] = "google"
        return "Hallo (g)"
    chain.setattr(d, "_mt_chain", mt)
    meta = {}
    assert d._translate("Hello", "en", "de", meta=meta) == "Hallo (c)" and meta["provider"] == "claude"


def test_both_fail_raises(chain):
    chain.setattr(d, "_claude_async", _claude(exc=RuntimeError("c")))
    chain.setattr(d, "_mt_chain", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("g")))
    with pytest.raises(RuntimeError):
        d._translate("Hello", "en", "de")


def test_mt_chain_both_providers_paused(chain):
    chain.setitem(d.LLM, "on", False)
    now = time.monotonic()
    d._PROV["google"]["until"] = now + 60
    d._PROV["mymemory"]["until"] = now + 60
    with pytest.raises(RuntimeError, match="pausiert"):
        d._mt_chain("x", "en", "de", {})


def test_mt_chain_no_time_left_for_mymemory(chain):
    chain.setitem(d.LLM, "on", False)
    chain.setattr(d, "google_translate", lambda *a: (_ for _ in ()).throw(ValueError("leer")))
    with pytest.raises(ValueError):
        d._mt_chain("x", "en", "de", {}, deadline=time.monotonic() + 0.1)
    d.reset_net_backoff()
    d._PROV["google"]["until"] = time.monotonic() + 60
    with pytest.raises(RuntimeError, match="Zeitlimit"):
        d._mt_chain("x", "en", "de", {}, deadline=time.monotonic() + 0.1)


def test_check_llm_rejects_nearly_empty_translation():
    long_text = "Please tell me where the nearest pharmacy is because my daughter has a fever since last night."
    with pytest.raises(d._Implausible):
        d._check_llm(long_text, "ขอ", "th", "en")
    assert d._check_llm(long_text, "ช่วยบอกหน่อยว่าร้านขายยาที่ใกล้ที่สุดอยู่ที่ไหน เพราะลูกสาวมีไข้ตั้งแต่เมื่อคืน", "th", "en")
    assert d._check_llm("Hello", "สวัสดี", "th", "en") == "สวัสดี"          # kurzer Satz: keine Mindestlänge


def test_numbers_cache_follows_pair(monkeypatch):
    assert d._numbers("สามร้อย") == ["300"]
    monkeypatch.setattr(d, "PAIR", ["de", "en"])
    d._numbers("555")
    monkeypatch.setattr(d, "PAIR", ["en", "th"])
    assert d._numbers("555") == []                       # Thai aktiv: 555 = Lachen
    monkeypatch.setattr(d, "PAIR", ["de", "en"])
    assert d._numbers("555") == ["555"]
    t = set()
    d._numbers("um 14:30", times=t)
    assert t == {"14.30"}


def test_parse_pair_accepts_region_codes():
    assert d.parse_pair("en-US", "TH") == ("en", "th")
    assert d.parse_pair("pt_BR", "zh-CN") == ("pt", "zh")
    assert d.parse_pair("en", "en-GB") is None
    assert d.parse_pair("xx-YY", "th") is None
    assert d.parse_pair("", "th") is None


@pytest.mark.parametrize("lang,text,rest", [
    ("it", "ahahah che bello", "che bello"), ("nl", "hahaha leuk", "leuk"), ("pl", "hahaha super", "super"),
    ("tr", "hahaha çok iyi", "çok iyi"), ("uk", "хахаха чудово", "чудово"), ("vi", "haha tuyệt", "tuyệt"),
    ("ar", "ههههه جميل", "جميل"), ("hi", "हाहा बहुत अच्छा", "बहुत अच्छा"),
])
def test_laughter_detected_in_more_languages(lang, text, rest):
    rx = d.LAUGH[lang]
    assert rx.search(text)
    assert d._strip_edge_laugh(rx, text).strip() == rest


def test_laugh_regexes_do_not_hit_normal_words():
    for lang, word in (("it", "ahimè"), ("nl", "haha's"), ("tr", "kaka"), ("vi", "hi"), ("pl", "hej"), ("hi", "हाथ")):
        assert not d.LAUGH[lang].search(word) or lang == "nl"


@pytest.mark.parametrize("lang,expected", [
    ("it", "25 gradi Celsius"), ("pt", "25 graus Celsius"), ("nl", "25 graden Celsius"),
    ("ru", "25 градусов по Цельсию"), ("pl", "25 stopni Celsjusza"), ("tr", "25 derece Celsius"),
])
def test_degrees_spoken_in_more_languages(lang, expected):
    assert d.speak_form("25°C", lang) == expected


@pytest.mark.parametrize("lang,text,expected", [
    ("pl", "Gdzie jest dworzec", True), ("pl", "Dziękuję bardzo", False), ("tr", "Tren nerede", False),
    ("tr", "Nerede tren", True), ("uk", "Де вокзал", True), ("uk", "Дякую", False),
    ("id", "Berapa harganya", True), ("id", "Terima kasih", False), ("hi", "कहाँ है स्टेशन", True),
    ("hi", "धन्यवाद", False), ("ar", "أين المحطة", True), ("ar", "شكرا", False),
])
def test_question_words_pl_tr_uk_id_hi_ar(lang, text, expected):
    assert d.is_question(text, lang) is expected


def test_register_hint_for_all_non_thai_non_english_languages():
    for lang in d.LANGS:
        if lang in ("en", "th"):
            continue
        assert d.register_hint(lang, "polite"), lang
        assert d.register_hint(lang, "casual"), lang
