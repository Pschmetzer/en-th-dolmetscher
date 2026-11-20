"""Übersetzung und Textverarbeitung: Lachen/555, Zahlen, Glossar, Cache, Plausibilität (ohne Netz)."""
import urllib.parse

import pytest

import dolmetscher as d


@pytest.fixture(autouse=True)
def _iso(monkeypatch):
    monkeypatch.setattr(d, "_CACHE", d.collections.OrderedDict())
    monkeypatch.setitem(d.LLM, "on", False)
    monkeypatch.setattr(d, "GLOSSARY", [])
    monkeypatch.setattr(d, "_GLOSSARY_OWN", None)
    monkeypatch.setattr(d, "emit", lambda ev, **kw: None)


def _google_echo(seen, answer=None):
    """Fake-Google: merkt sich den gesendeten Text und antwortet mit `answer(text)`."""
    def gj(url, timeout=0):
        q = urllib.parse.unquote(url.split("q=")[1].split("&")[0])
        seen.append(q)
        return [[[answer(q) if answer else "ผลลัพธ์", "x"]]]
    return gj


# ---- 555 -----------------------------------------------------------------------------------------

@pytest.mark.parametrize("text", ["ราคา 555 บาท", "ห้อง 555", "เที่ยวบิน 555 ช้า", "เบอร์ 555 นะ", "1,555 บาท",
                                  "โทรมา 081-555-1234", "โทรมา 081 555 1234"])
def test_555_as_number_is_kept(monkeypatch, text):
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "Price 555 baht"))
    out = d.translate(text, "th", "en")
    assert seen == [text] and "haha" not in out


@pytest.mark.parametrize("text, sent", [("555", None), ("ดีมาก 555", "ดีมาก"), ("555 ไปไหนมา", "ไปไหนมา"),
                                        ("ตลกมาก 55555", "ตลกมาก"), ("ฮ่าๆ", None)])
def test_555_as_laugh(monkeypatch, text, sent):
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "Very good"))
    out = d.translate(text, "th", "en")
    assert out.endswith("haha") and seen == ([sent] if sent else [])


@pytest.mark.parametrize("a, b, differ", [
    ("ราคา 555 บาท", "Price 555 baht", False),
    ("ห้อง 555", "room 55", True),
    ("ราคา 100 555", "price 100 haha", False),
    ("2:30 PM", "14:30", False),
    ("at 2:30 PM", "บ่าย 2:30", False),
    ("9am", "09:00", False),
    ("3.5 km", "3,5 กม.", False),
    ("1.5", "15", True),
    ("350 baht", "530 บาท", True),
    ("two kids, 350 baht", "ลูก 2 คน 350 บาท", False),        # einstellige Zahl als Wort/Ziffer
    ("ten minutes", "10 นาที", False),
])
def test_numbers_differ_robust(a, b, differ):
    assert d.numbers_differ(a, b) is differ


# ---- Glossar -------------------------------------------------------------------------------------

def test_glossary_hits_word_boundaries(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Pat", None), ("Ao", "อ้อ"), ("สุขุมวิท", None)])
    assert d.glossary_hits("the path to Patrick") == []
    assert d.glossary_hits("also") == []
    assert d.glossary_hits("Hi pat!") == [("Pat", None)]
    assert d.glossary_hits("บ้านอยู่ที่สุขุมวิทนะ") == [("สุขุมวิท", None)]


def test_glossary_placeholders_with_google(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Nok", "น้อก"), ("Sukhumvit", None)])
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "โทรหา [1] ที่ [2] พรุ่งนี้"))
    out = d.translate("Call Nok in Sukhumvit tomorrow", "en", "th")
    assert seen == ["Call [1] in [2] tomorrow"]
    assert out == "โทรหา น้อก ที่ Sukhumvit พรุ่งนี้"


def test_glossary_reverse_direction(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Nok", "น้อก")])
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "[1] is coming"))
    assert d.translate("น้อก กำลังมา", "th", "en") == "Nok is coming"


def test_glossary_placeholder_lost_retranslates(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Nok", None)])
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "สวัสดีนก" if "[1]" in q else "สวัสดี Nok"))
    assert d.translate("Hello Nok", "en", "th") == "สวัสดี Nok"
    assert seen == ["Hello [1]", "Hello Nok"]


def test_glossary_only_names_skips_mt(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Nok", "น้อก")])
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: pytest.fail("kein Netz nötig"))
    assert d.translate("Nok!", "en", "th") == "น้อก!"


def test_glossary_written_atomic_and_private(tmp_path, monkeypatch):
    f = tmp_path / "sub" / "g.txt"
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(f))
    d.load_glossary("Nok => น้อก\n")
    assert f.read_text(encoding="utf-8") == "Nok => น้อก\n"
    assert (f.stat().st_mode & 0o777) == 0o600
    assert [p.name for p in f.parent.iterdir()] == ["g.txt"]          # keine Temp-Reste


def test_pronounce_word_boundaries_single_pass(monkeypatch):
    monkeypatch.setattr(d, "PRONOUNCE", [("Pat", "Pät"), ("Pät", "X"), ("New York", "Nju York")])
    assert d.apply_pronounce("Pat likes the pattern in new york") == "Pät likes the pattern in Nju York"


# ---- Cache ---------------------------------------------------------------------------------------

def test_cache_key_keeps_question_mark(monkeypatch):
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "คุณมาไหม" if "?" in q else "คุณมา"))
    assert d.translate("You're coming.", "en", "th") == "คุณมา"
    assert d.translate("You're coming?", "en", "th") == "คุณมาไหม"
    meta = {}
    assert d.translate("you're coming ?", "en", "th", meta=meta) == "คุณมาไหม" and meta.get("cached")
    assert len(seen) == 2


def test_cache_not_served_after_glossary_change(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(tmp_path / "g.txt"))
    d.load_glossary("")
    d._cache_put(d._cache_key("x", "en", "th", False, "krub"), ("y", "google"))
    assert d._cache_get(d._cache_key("x", "en", "th", False, "krub")) == ("y", "google")
    d.load_glossary("Nok")
    # der alte Eintrag passt nicht mehr zum neuen Glossar (Schlüssel trägt die Signatur) ...
    assert d._cache_get(d._cache_key("x", "en", "th", False, "krub")) is None
    # ... und kommt zurück, wenn das Glossar wieder dem alten entspricht (Cache nicht geleert)
    d.load_glossary("")
    assert d._cache_get(d._cache_key("x", "en", "th", False, "krub")) == ("y", "google")


# ---- fix_thai: Geschlecht konsequent ---------------------------------------------------------------

@pytest.mark.parametrize("src, krub, ka", [
    ("สวัสดีค่ะ", "สวัสดีครับ", "สวัสดีค่ะ"),
    ("ผมหิวครับ", "ผมหิวครับ", "ฉันหิวค่ะ"),
    ("ฉันชอบคะแนนนี้ค่ะ", "ผมชอบคะแนนนี้ครับ", "ฉันชอบคะแนนนี้ค่ะ"),     # คะแนน bleibt
    ("ตัดผมแล้วครับ", "ตัดผมแล้วครับ", "ตัดผมแล้วค่ะ"),                  # ผม = Haar bleibt
    ("ผมยาวมาก", "ผมยาวมาก", "ผมยาวมาก"),
    ("ผม ไปก่อนนะครับ", "ผม ไปก่อนนะครับ", "ฉัน ไปก่อนนะคะ"),
    ("คุณมาค่ะ?", "คุณมาครับ?", "คุณมาคะ?"),                             # ? aus dem Original
    ("ครับผม", "ครับผม", "ค่ะ"),
    ("ดิฉันชื่อน้อย", "ผมชื่อน้อย", "ดิฉันชื่อน้อย"),
])
def test_fix_thai_gender_consistent(src, krub, ka):
    assert d.fix_thai(src, "krub") == krub
    assert d.fix_thai(src, "ka") == ka


# ---- JUNK ----------------------------------------------------------------------------------------

@pytest.mark.parametrize("text", ["Thanks for watching!", "thank you for watching everyone",
                                  "ขอบคุณที่ติดตามรับชมนะครับ", "อย่าลืมกดไลค์ กดแชร์", "Please subscribe."])
def test_junk_variants(text):
    assert text in d.JUNK


@pytest.mark.parametrize("text", ["thanks for watching the kids", "hello", "", "Music festival", "ขอบคุณครับ"])
def test_junk_keeps_real_speech(text):
    assert text not in d.JUNK


# ---- Claude-Plausibilität, Kosten, Namen -----------------------------------------------------------

@pytest.mark.parametrize("claude_out", ["I'm sorry, I can't help with translating that.",
                                        "Hello, how are you today?",                      # nicht Thai
                                        "สวัสดี\n\nNote: casual register"])
def test_implausible_claude_falls_back_to_google(monkeypatch, claude_out):
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    monkeypatch.setattr(d, "claude_translate", lambda *a: claude_out)
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: [[["สวัสดีครับ", "x"]]])
    meta = {}
    assert d.translate("Hello, how are you today?", "en", "th", meta=meta) == "สวัสดีครับ"
    assert meta["provider"] == "google" and d.LLM["skip_until"] <= d.time.monotonic()   # keine Claude-Pause


def test_claude_translation_prefix_stripped(monkeypatch):
    assert d._check_llm("ขอโทษนะ", "Translation: I'm sorry", "en") == "I'm sorry"


def test_cost_counts_cache_tokens(monkeypatch):
    import types
    u = types.SimpleNamespace(input_tokens=1_000_000, output_tokens=0, cache_read_input_tokens=1_000_000,
                              cache_creation_input_tokens=1_000_000)
    r = types.SimpleNamespace(usage=u, stop_reason="end_turn", content=[types.SimpleNamespace(type="text", text="ok")])
    client = types.SimpleNamespace(messages=types.SimpleNamespace(create=lambda **k: r))
    monkeypatch.setattr(d, "llm_client", lambda: client)
    monkeypatch.setitem(d.LLM, "model", "claude-haiku-5-5")
    monkeypatch.setitem(d.LLM, "usd", 0.0)
    d.claude_translate("hi", "en", "th")
    pin = d.LLM_PRICE["claude-haiku-5-5"][0]
    assert d.LLM["usd"] == pytest.approx(pin * (1 + 0.1 + 1.25))


@pytest.mark.parametrize("name", ["Hotel California", "Grab"])
def test_google_keeps_names(monkeypatch, name):
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: [[[name, "x"]]])
    meta = {}
    assert d.translate(name, "en", "th", meta=meta) == name and meta["provider"] == "google"


def test_keyfile_made_private(tmp_path, monkeypatch):
    k = tmp_path / "key"
    k.write_text("x")
    k.chmod(0o644)
    monkeypatch.setattr(d, "KEYFILE", str(k))
    d._private_keyfile()
    assert (k.stat().st_mode & 0o777) == 0o600


# ---- KeepAlive (ohne Netz, mit Fake-Verbindung) -----------------------------------------------------

class _Resp:
    def __init__(self, status, body, ctype="application/json"):
        self.status, self.reason, self._body, self.will_close = status, "x", body, False
        self.headers = {"Content-Type": ctype}

    def read(self, n=-1):
        return self._body

    def getheader(self, k, default=None):
        return self.headers.get(k, default)


def _fake_conn(log, answers):
    class Conn:
        def __init__(self, host, port=None, timeout=None):
            self.host, self.sock, self.timeout = host, None, timeout
            log.append(("new", host))

        def set_tunnel(self, host, port, headers=None):
            log.append(("tunnel", host, port, bool(headers)))

        def request(self, method, path, body=None, headers=None):
            self.last = (method, path, body)
            log.append(("req", method, path, body))

        def getresponse(self):
            return answers.pop(0)(self.last) if callable(answers[0]) else answers.pop(0)

        def close(self):
            pass
    return Conn


@pytest.fixture
def ka(monkeypatch):
    log, answers = [], []
    monkeypatch.setattr(d.http.client, "HTTPSConnection", _fake_conn(log, answers))
    monkeypatch.setattr(d.urllib.request, "getproxies", lambda: {})
    return d.KeepAlive(), log, answers


def test_keepalive_posts_text_not_in_url(ka):
    http, log, answers = ka
    answers.append(_Resp(200, b'[[["x","y"]]]'))
    url = "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t&sl=en&tl=th&q=" + \
          urllib.parse.quote("secret words")
    assert http.get_json(url, 3) == [[["x", "y"]]]
    _, method, path, body = [x for x in log if x[0] == "req"][0]
    assert method == "POST" and "secret" not in path and "q=" not in path and b"secret" in body
    assert "sl=en" in path


def test_keepalive_falls_back_to_get_and_reuses(ka):
    http, log, answers = ka
    answers += [_Resp(405, b""), _Resp(200, b"{}"), _Resp(200, b"{}")]
    url = "https://api.mymemory.translated.net/get?q=hi&langpair=en|th"
    assert http.get_json(url, 3) == {} and http.get_json(url, 3) == {}
    reqs = [x for x in log if x[0] == "req"]
    assert [r[1] for r in reqs] == ["POST", "GET", "GET"] and "q=hi" in reqs[1][2]
    assert sum(1 for x in log if x[0] == "new") == 1                 # Verbindung wiederverwendet


def test_keepalive_not_json_and_redirect(ka):
    http, log, answers = ka
    answers += [_Resp(200, b"<html>Sorry</html>", "text/html"), _Resp(302, b"")]
    with pytest.raises(d.NotJSON, match="unerwartet"):
        http.get_json("https://example.org/x", 3)
    with pytest.raises(d.urllib.error.HTTPError):
        http.get_json("https://example.org/x", 3)


def test_keepalive_uses_proxy(ka, monkeypatch):
    http, log, answers = ka
    monkeypatch.setattr(d.urllib.request, "getproxies", lambda: {"https": "http://u:p@proxy.local:3128"})
    monkeypatch.setattr(d.urllib.request, "proxy_bypass", lambda h: False)
    answers.append(_Resp(200, b"{}"))
    http.get_json("https://example.org/x", 3)
    assert ("new", "proxy.local") in log and ("tunnel", "example.org", 443, True) in log


def test_keepalive_no_global_lock_during_request(ka):
    """Während eine Anfrage an Host A läuft, darf Host B nicht warten."""
    import threading
    http, log, answers = ka
    started, release = threading.Event(), threading.Event()

    def slow(last):
        started.set()
        release.wait(2)
        return _Resp(200, b"{}")
    answers += [slow, _Resp(200, b"[]")]
    t = threading.Thread(target=http.get_json, args=("https://a.example/x", 3))
    t.start()
    assert started.wait(2)
    assert http.get_json("https://b.example/y", 3) == []              # kommt durch, obwohl A hängt
    release.set()
    t.join(2)


# ---- _emit / _logger ---------------------------------------------------------------------------------

def test_emit_numpy_and_broken_pipe(monkeypatch, capsys):
    import json

    import numpy as np
    monkeypatch.setattr(d, "JSON", True)
    d._emit("level", rms=np.float32(0.5), n=np.int64(3), arr=np.array([1, 2]))
    assert json.loads(capsys.readouterr().out) == {"event": "level", "rms": 0.5, "n": 3, "arr": [1, 2]}

    def boom(*a, **k):
        raise BrokenPipeError
    monkeypatch.setattr("builtins.print", boom)
    monkeypatch.setattr(d, "STOP", d.threading.Event())
    d._emit("x")
    assert d.STOP.is_set()


_ORIG_LOGGER = d._logger          # vor dem autouse-Null-Logger aus conftest gemerkt


def test_logger_single_handler_with_date(tmp_path, monkeypatch):
    import threading
    monkeypatch.setattr(d, "LOGFILE", str(tmp_path / "e.log"))
    monkeypatch.setattr(d, "_LOGGER", None)
    lg = d.logging.getLogger("dolmetscher")
    before = list(lg.handlers)
    try:
        ts = [threading.Thread(target=_ORIG_LOGGER) for _ in range(8)]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        mine = [h for h in lg.handlers if isinstance(h, d._PrivateRotatingHandler)]
        assert len(mine) == 1 and "%Y-%m-%d" in mine[0].formatter.datefmt
    finally:
        for h in lg.handlers[:]:
            if h not in before:
                lg.removeHandler(h)
                h.close()


# ---- Hedging: Claude langsam -> Google -------------------------------------------------------------

@pytest.fixture
def slow_claude(monkeypatch):
    import threading
    gate = threading.Event()
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setitem(d.LLM, "hedge_s", 0.05)
    monkeypatch.setattr(d, "llm_available", lambda: True)

    def claude(*a):
        gate.wait(2)
        return "ไปไหนมาครับ"
    monkeypatch.setattr(d, "claude_translate", claude)
    yield gate
    gate.set()


def test_hedge_takes_google_when_claude_slow(monkeypatch, slow_claude):
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: [[["ไปไหนมา", "x"]]])
    meta = {}
    t0 = d.time.monotonic()
    assert d.translate("Where have you been?", "en", "th", meta=meta) == "ไปไหนมา"
    assert meta["provider"] == "google" and d.time.monotonic() - t0 < 1.0
    assert d._cache_get(d._cache_key("Where have you been?", "en", "th", False, "krub"))   # als MT gemerkt


def test_hedge_waits_for_claude_when_mt_fails(monkeypatch, slow_claude):
    def offline(u, t=0):
        slow_claude.set()                       # Claude antwortet, während Google/MyMemory scheitern
        raise d.urllib.error.URLError("no route")
    monkeypatch.setattr(d, "_get_json", offline)
    meta = {}
    assert d.translate("Where have you been?", "en", "th", meta=meta) == "ไปไหนมาครับ"
    assert meta["provider"] == "claude"


def test_hedge_default_depends_on_model(monkeypatch):
    monkeypatch.setitem(d.LLM, "hedge_s", None)
    monkeypatch.setitem(d.LLM, "model", "claude-haiku-5-5")
    fast = d._hedge_s()
    monkeypatch.setitem(d.LLM, "model", "claude-opus-5-5")
    assert d._hedge_s() > fast


def test_preset_glossary_stays_claude_only(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(tmp_path / "g.txt"))
    d.load_glossary("Nok => น้อก")
    d.GLOSSARY.append(("room", "ห้อง"))                     # so hängt PresetState Preset-Wörter an
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "Where is the bathroom?"))
    d.translate("ห้องน้ำอยู่ไหน", "th", "en")
    assert seen == ["ห้องน้ำอยู่ไหน"]
    assert d.glossary_hits("room service") == [("room", "ห้อง")]  # Claude bekommt es weiter


def test_claude_real_apology_kept():
    assert d._check_llm("ขอโทษนะ ช่วยหน่อยได้ไหม", "Sorry, can you help me?", "en") == "Sorry, can you help me?"
    with pytest.raises(d._Implausible):
        d._check_llm("ขอโทษนะ", "I'm sorry, but I can't translate that.", "en")


def test_split_sentences_keeps_abbreviations():
    s = "Mr. Smith and Dr. Brown are waiting in the lobby downstairs. They want to talk about the room."
    parts = d.split_sentences(s, "en")
    assert parts[0].startswith("Mr. Smith and Dr. Brown") and len(parts) == 2
