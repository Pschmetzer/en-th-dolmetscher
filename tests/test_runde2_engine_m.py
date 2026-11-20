"""Runde 2, Engine M-Punkte: Uhrzeiten im Zahlenvergleich (21), Gegenprobe bei abweichenden Zahlen (25),
Hedging (22), nur bei fehlendem Modell herunterladen (17), edge-tts-Selbsttest (20), Höflichkeitsform je
Profil (162)."""
import concurrent.futures
import threading
import time
import types

import pytest

import dolmetscher as d
import profiles


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


# --- 21 ---------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("a,b", [
    ("See you at 8 pm", "เจอกันสองทุ่มนะ"),
    ("at 3 a.m.", "ตีสาม"),
    ("half past three", "บ่ายสามโมงครึ่ง"),
    ("at 17:00", "ห้าโมงเย็น"),
    ("meet at noon", "เที่ยงวัน"),
    ("8 o'clock", "สองทุ่ม"),
    ("quarter to nine", "8:45"),
    ("at midnight", "เที่ยงคืน"),
    ("1 pm", "บ่ายโมง"),
    ("See you at 8", "เจอกันสองทุ่มนะ"),     # nackte Stunde gegen Thai-Zeit (vorher kein Alarm)
    ("um 8 Uhr", "สองทุ่ม"),
])
def test_uhrzeiten_gelten_als_gleich(a, b):
    assert not d.numbers_differ(a, b)


@pytest.mark.parametrize("a,b", [
    ("at 8 pm", "ตีสอง"),                    # 20:00 gegen 2:00
    ("half past three", "สี่โมงครึ่ง"),        # 3:30 gegen 4:30
    ("It costs 300 baht", "ราคา 500 บาท"),
])
def test_echte_abweichung_bleibt(a, b):
    assert d.numbers_differ(a, b)


def test_zeitraum_ist_keine_uhrzeit():
    assert d.clock_words_to_24h("สองชั่วโมง") == "สองชั่วโมง"
    assert "15" not in d._numbers("15 minutes") or d._numbers("15 minutes") == ["15"]


# --- 25 ---------------------------------------------------------------------------------------------------

def test_gegenprobe_nimmt_zahlentreue_fassung(monkeypatch):
    monkeypatch.setattr(d, "_mt_chain", lambda text, src, dst, meta, deadline=None:
                        meta.update(provider="google") or "ราคา 300 บาท")
    meta = {"provider": "claude"}
    out = d.recheck_numbers("It costs 300 baht", "en", "th", "ราคา 500 บาท", meta)
    assert out == "ราคา 300 บาท" and meta["provider"] == "google" and meta["rechecked"]


def test_gegenprobe_behaelt_erste_fassung_bei_fehler_oder_abweichung(monkeypatch):
    monkeypatch.setattr(d, "_mt_chain", lambda *a, **k: "ราคา 700 บาท")
    meta = {"provider": "claude"}
    assert d.recheck_numbers("It costs 300 baht", "en", "th", "ราคา 500 บาท", meta) == "ราคา 500 บาท"
    assert meta == {"provider": "claude"}

    def boom(*a, **k):
        raise RuntimeError("offline")
    monkeypatch.setattr(d, "_mt_chain", boom)
    assert d.recheck_numbers("It costs 300 baht", "en", "th", "x 5", {"provider": "claude"}) == "x 5"
    # Google zuerst, Claude aus: keine Gegenprobe
    monkeypatch.setitem(d.LLM, "on", False)
    assert d.recheck_numbers("300", "en", "th", "500", {"provider": "google"}) == "500"


def test_gegenprobe_mit_claude_nach_google(monkeypatch):
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    f = concurrent.futures.Future()
    f.set_result("ราคา 300 บาท")
    monkeypatch.setattr(d, "_claude_async", lambda *a: f)
    meta = {"provider": "google"}
    assert d.recheck_numbers("It costs 300 baht", "en", "th", "ราคา 500 บาท", meta) == "ราคา 300 บาท"
    assert meta["provider"] == "claude"


# --- 22: Hedging -----------------------------------------------------------------------------------------

def _hedge_setup(monkeypatch, claude, google):
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setitem(d.LLM, "hedge_s", 0.05)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    monkeypatch.setattr(d, "_cache_get", lambda k: None)
    monkeypatch.setattr(d, "_cache_put", lambda k, v: None)

    waits = []                                   # Zeitlimits, mit denen _translate auf Claude wartet

    class Fut(concurrent.futures.Future):
        def result(self, timeout=None):
            waits.append(timeout)
            return super().result(timeout)

    def fake_claude(text, src, dst, history, alts, polite):
        f = Fut()
        delay, res = claude

        def done():
            if isinstance(res, Exception):
                f.set_exception(res)
            else:
                f.set_result(res)
        if delay == 0:
            done()                               # sofort fertig: unabhängig vom Thread-Takt des Rechners
        elif delay is None:
            release.append(done)                 # kommt erst nach den Prüfungen (Test gibt frei)
        else:
            threading.Timer(delay, done).start()
        return f
    release = []
    monkeypatch.setattr(d, "_claude_async", fake_claude)

    def fake_mt(text, src, dst, meta, deadline=None):
        if isinstance(google, Exception):
            raise google
        meta["provider"] = "google"
        return google
    monkeypatch.setattr(d, "_mt_chain", fake_mt)
    return waits, release


def test_hedge_claude_schnell(monkeypatch):
    _hedge_setup(monkeypatch, (0.0, "C"), "G")
    meta = {}
    assert d._translate("hi", "en", "th", meta=meta) == "C" and meta["provider"] == "claude"


def test_hedge_claude_langsam_google_gewinnt(monkeypatch):
    waits, release = _hedge_setup(monkeypatch, (None, "C"), "G")   # Claude antwortet erst nach den Prüfungen
    meta = {}
    try:
        assert d._translate("hi", "en", "th", meta=meta) == "G" and meta["provider"] == "google"
        # Nur die Hedging-Frist abgewartet, danach nie mehr auf Claude (statt Zeitmessung auf der echten Uhr)
        assert waits == [d.LLM["hedge_s"]]
    finally:
        for f in release:
            f()


def test_hedge_google_fehlt_claude_kommt_spaet(monkeypatch):
    _hedge_setup(monkeypatch, (0.2, "C"), RuntimeError("google kaputt"))
    meta = {}
    assert d._translate("hi", "en", "th", meta=meta) == "C" and meta["provider"] == "claude"


def test_hedge_beide_fehler(monkeypatch):
    _hedge_setup(monkeypatch, (0.2, RuntimeError("claude kaputt")), RuntimeError("google kaputt"))
    with pytest.raises(RuntimeError):
        d._translate("hi", "en", "th", meta={})


def test_hedge_claude_fehler_sofort_google(monkeypatch, ev):
    _hedge_setup(monkeypatch, (0.0, RuntimeError("claude kaputt")), "G")
    meta = {}
    assert d._translate("hi", "en", "th", meta=meta) == "G"
    assert d.LLM["skip_until"] > time.monotonic()          # Backoff gesetzt


# --- 17 ---------------------------------------------------------------------------------------------------

class LocalEntryNotFoundError(Exception):
    pass


def test_nur_fehlendes_modell_laedt_herunter(monkeypatch, ev):
    calls = []

    def fake_wm(model, local_files_only=False, **kw):
        calls.append(local_files_only)
        if local_files_only:
            raise ValueError("Requested float16 compute type, but the target device does not support it")
        return "M"
    monkeypatch.setattr(d, "WhisperModel", fake_wm)
    monkeypatch.setattr(d, "_DOWNLOAD_SAID", {})
    with pytest.raises(ValueError):
        d._wm("small")
    assert calls == [True] and not [e for e, kw in ev if kw.get("download")]


def test_fehlendes_modell_wird_geladen(monkeypatch, ev):
    calls = []

    def fake_wm(model, local_files_only=False, **kw):
        calls.append(local_files_only)
        if local_files_only:
            raise LocalEntryNotFoundError("Cannot find an appropriate cached snapshot folder")
        return "M"
    monkeypatch.setattr(d, "WhisperModel", fake_wm)
    monkeypatch.setattr(d, "_DOWNLOAD_SAID", {})
    assert d._wm("small") == "M" and calls == [True, False]
    assert [kw for e, kw in ev if e == "loading" and kw.get("download")]


def test_missing_locally_folgt_ursache():
    try:
        try:
            raise FileNotFoundError("model.bin")
        except FileNotFoundError as e:
            raise RuntimeError("load failed") from e
    except RuntimeError as e:
        assert d.missing_locally(e)
    assert not d.missing_locally(RuntimeError("MPS backend out of memory"))


# --- 20 ---------------------------------------------------------------------------------------------------

def test_edge_tts_selbsttest(monkeypatch):
    pytest.importorskip("edge_tts")
    pytest.importorskip("aiohttp")
    monkeypatch.setitem(d._WS, "ok", True)
    assert d.edge_tts_selftest() is True and d._WS["ok"]
    from edge_tts import communicate as ec
    monkeypatch.delattr(ec, "_SSL_CTX")
    assert d.edge_tts_selftest() is False and d._WS["ok"] is False


# --- 162 --------------------------------------------------------------------------------------------------

def test_hoeflichkeit_nach_profil(monkeypatch):
    e = d.Engine.__new__(d.Engine)
    me, her = {"name": "Pat", "polite": "krub"}, {"name": "Joy", "polite": "ka"}
    e.spk = types.SimpleNamespace(me=lambda: me, partner=lambda: her)
    assert e._speaker_polite(her, None) == "ka"
    assert e._speaker_polite(None, "me") == "krub"
    assert e._speaker_polite({"name": "X"}, "other") is None
    e.spk = None
    assert e._speaker_polite(None, "me") is None


def test_deliver_nutzt_profil_hoeflichkeit(monkeypatch, ev):
    seen = []
    monkeypatch.setattr(d, "translate", lambda text, src, dst, **k: seen.append(k["polite"]) or "สวัสดีครับ")
    e = d.Engine.__new__(d.Engine)
    e.texts, e.history, e.translate_dir, e.polite = {}, [], {}, "krub"
    e.speaker = types.SimpleNamespace(add=lambda *a, **k: None)
    monkeypatch.setattr(d, "PAIR", ["en", "th"])
    e.deliver("u1", "en", "Hello", speak=False, polite="ka")
    out = [kw for x, kw in ev if x == "utt"][0]["out"]
    assert seen == ["ka"] and "ค่ะ" in out


def test_set_polite_im_profil(monkeypatch, tmp_path):
    store = {"Joy": {"name": "Joy", "lang": "th", "vocab": []}}
    monkeypatch.setattr(profiles, "get_profile", lambda n: store.get(n))
    monkeypatch.setattr(profiles, "save_profile", lambda p: store.__setitem__(p["name"], p))
    assert profiles.set_polite("Joy", "ka")["polite"] == "ka"
    assert profiles.public(store["Joy"])["polite"] == "ka"
    assert "polite" not in profiles.set_polite("Joy", "-")
    with pytest.raises(ValueError):
        profiles.set_polite("Joy", "sir")
    with pytest.raises(KeyError):
        profiles.set_polite("Nobody", "ka")
