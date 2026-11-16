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


# --- 62: Log-Filter rekursiv ---------------------------------------------------------------------------------

def test_log_filter_verschachtelt(monkeypatch):
    seen = []
    monkeypatch.setattr(d, "LOG_TEXT", False)
    monkeypatch.setattr(d, "_logger", lambda: types.SimpleNamespace(info=seen.append))
    d.log({"utt": {"text": "geheim", "n": 3, "alts": [{"text": "auch geheim"}]}, "hyps": [{"out": "x y"}],
           "ok": "bleibt"})
    s = seen[-1]
    assert "geheim" not in s and "x y" not in s and "bleibt" in s and '"n": 3' in s


# --- 57: Retry-After bei Claude-429/529 --------------------------------------------------------------------

def _api_err(code, ra=None):
    e = Exception("x")
    e.status_code = code
    e.response = types.SimpleNamespace(headers={"retry-after": ra} if ra is not None else {})
    return e


def test_claude_backoff_nutzt_retry_after():
    assert d._llm_backoff(_api_err(429, "7")) == 7.0
    assert d._llm_backoff(_api_err(529, "2")) == 2.0
    assert d._llm_backoff(_api_err(429)) == d.LLM_BACKOFF
    assert d._llm_backoff(_api_err(529)) == 20.0          # überlastet: kürzer als Ratelimit
    assert d._llm_backoff(_api_err(429, "99999")) == 600.0
    assert d._llm_backoff(_api_err(429, "abc")) == d.LLM_BACKOFF


# --- 53/54: Zahlenvergleich ----------------------------------------------------------------------------------

@pytest.mark.parametrize("a,b,differ", [
    ("table for 2", "โต๊ะสำหรับ 3 ที่", True),            # 53: beide Ziffern, einstellig
    ("table for 2", "โต๊ะสำหรับสองที่", False),           # als Wort übersetzt
    ("table for 2", "โต๊ะสำหรับ 2 ที่", False),
    ("I have 2 kids", "ฉันมีลูก", False),                 # nur eine Seite mit Zahl
    ("10k baht", "หนึ่งหมื่นบาท", False),                # 54
    ("10k baht", "10,000 บาท", False),
    ("10 thousand baht", "10000 บาท", False),
    ("20k baht", "หนึ่งหมื่นบาท", True),
    ("3 แสนบาท", "300,000 baht", False),
    ("2 หมื่น", "20,000", False),
    ("5 พันบาท", "5,000 baht", False),
    ("1.5 ล้าน", "1.5 million", False),
    ("5 km", "5 กิโลเมตร", False),                        # km ist kein k
])
def test_numbers_runde4(a, b, differ):
    assert d.numbers_differ(a, b) is differ


# --- 55: Floskeln ----------------------------------------------------------------------------------------------

@pytest.mark.parametrize("t", ["Thanks for listening!", "ขอบคุณที่ดูนะคะ", "Subtitles by Somchai",
                               "subtitles by the amara.org community"])
def test_floskeln_runde4(t):
    low = d._strip_punct(t).lower()
    assert low in d.JUNK or d._JUNK_BY.fullmatch(d._junk_norm(low))


def test_floskel_nur_ganze_aeusserung():
    low = d._strip_punct("thanks for listening to my problem").lower()
    assert low not in d.JUNK and not d._JUNK_BY.fullmatch(d._junk_norm("subtitles are bad"))


# --- 52: 555 vorlesen ----------------------------------------------------------------------------------------

def test_555_als_lachen_vorlesen():
    assert d.speak_form("ตลกมาก 555", "th") == "ตลกมาก ฮ่าฮ่าฮ่า"
    assert d.speak_form("ห้อง 555 ครับ", "th") == "ห้อง 555 ครับ"      # Zimmernummer bleibt
    assert d.speak_form("555 baht", "en") == "555 baht"


# --- 48: play_span nur im Debug ----------------------------------------------------------------------------

def test_play_span_nur_debug(monkeypatch):
    seen = []
    monkeypatch.setattr(d, "log", seen.append)
    monkeypatch.setattr(d, "DEBUG", False)
    pl = d.Player()
    class P:
        def wait(self, timeout=None):
            return 0
    p = P()
    pl.procs[p] = d.time.time()
    pl.wait(p)
    assert not any("play_span" in x for x in seen) and pl.spans


# --- 36: Websocket-Zeitlimit je Nachricht -------------------------------------------------------------------

def test_ws_haengt_nach_erstem_block(monkeypatch):
    import asyncio

    import aiohttp

    class WS:
        closed = False

        async def send_str(self, s):
            pass

        def __aiter__(self):
            async def gen():
                yield types.SimpleNamespace(type=aiohttp.WSMsgType.BINARY, data=b"\x00\x02xxAUDIO")
                await asyncio.sleep(30)                 # Server hängt
                yield None
            return gen()

    monkeypatch.setitem(d._WS, "pool", [])

    async def opened():
        return WS()
    monkeypatch.setattr(d, "_ws_open", opened)
    monkeypatch.setattr(d, "_spawn", lambda c: c.close())
    monkeypatch.setattr(d, "WS_RECV_S", 0.2)
    got = []
    t = d.time.monotonic()
    with pytest.raises(asyncio.TimeoutError):
        asyncio.run(d._ws_speak("<ssml/>", got.append, lambda: False))
    assert got == [b"AUDIO"] and d.time.monotonic() - t < 3
