"""Runde 7 (Engine): Regressionstests zu den Fehlern aus ideen/ergebnis-engine1.md und ergebnis-engine2.md.
Kein Netz, kein Modell, kein Mikrofon."""
import collections
import json
import os
import stat
import threading
import time
import types
import urllib.error

import numpy as np
import pytest

import correction_learning as cl
import dolmetscher as d
import history_store as hs
import hwprofile
import presets as P
import profiles


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def _eng(**kw):
    base = dict(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False, paused=False,
                rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False, beam=1)
    base.update(kw)
    return types.SimpleNamespace(**base)


# ---- Sprachbefehle (E1 1-4) ---------------------------------------------------------------------------------

@pytest.mark.parametrize("text,want", [
    ("don't translate", "pause"), ("not so fast", "slower"), ("too loud", "quieter"), ("too quiet", "louder"),
    ("too slow", "faster"), ("too fast", "slower"), ("mute off", "resume"), ("mute", "pause"),
    ("mute on", "pause"), ("sound off", "pause"), ("sound on", "resume"),
    ("play", "resume"), ("go ahead", "resume"), ("carry on", "resume"), ("can you start again", "resume"),
    ("one more time", "repeat"), ("what did you say", "repeat"), ("once more", "repeat"),
    ("volume 3", "volume:3"), ("speed 5", "speed:5"), ("volume 99", "volume:10"),
    ("don't stop", None), ("do not repeat", None), ("never pause", None), ("please don't pause", None),
    ("louder", "louder"), ("pause", "pause"), ("unmute", "resume"), ("translate both", "both_on"),
])
def test_parse_command_negation_und_varianten(text, want):
    assert d.parse_command(text) == want


# ---- Anführungszeichen, Namen, Länge (E1 13-15) ---------------------------------------------------------------

def test_strip_quotes_nur_ganzes_paar():
    assert d._strip_quotes('"Yes," he said, "no."') == '"Yes," he said, "no."'
    assert d._strip_quotes('"Hallo"') == "Hallo"
    assert d._strip_quotes("“Hi”") == "Hi"
    assert d._strip_quotes("Hallo") == "Hallo"


@pytest.mark.parametrize("text,want", [("Where Is The Toilet", False), ("Thank You", False),
                                       ("Chiang Mai", True), ("Fred", True)])
def test_looks_like_name_funktionswoerter(text, want):
    assert d._looks_like_name(text) is want


def test_check_llm_laenge_fuer_cjk():
    text = "你" * 60                                   # ~250 lateinische Zeichen als Übersetzung sind normal
    out = "word " * 50
    assert d._check_llm(text, out, "en", "zh").startswith("word")
    with pytest.raises(d._Implausible):
        d._check_llm("hi there", "word " * 50, "de", "en")


# ---- _split_bytes / MyMemory (E1 16, 48) ----------------------------------------------------------------------

def test_split_bytes_thai_schneidet_nicht_vor_vokalzeichen():
    t = "ยินดีที่ได้รู้จัก" * 40
    parts = d._split_bytes(t, 200)
    assert "".join(parts) == t                           # keine Leerzeichen eingefügt
    assert all(len(p.encode()) <= 200 for p in parts)
    assert all(not ("\u0e30" <= p[0] <= "\u0e3a" or "\u0e47" <= p[0] <= "\u0e4e") for p in parts)


def test_split_bytes_thai_fuehrende_vokale_bleiben_beim_konsonanten():
    for t in ("ได้" * 300, "เมื่อไหร่" * 100, "โรงแรมอยู่ที่ไหน" * 40):
        parts = d._split_bytes(t, 200)
        assert "".join(parts) == t
        assert all(not ("\u0e40" <= p[-1] <= "\u0e44") for p in parts)       # nie nach เ แ โ ใ ไ geschnitten
        assert all(not ("\u0e30" <= p[0] <= "\u0e3a" or "\u0e47" <= p[0] <= "\u0e4e") for p in parts)


def test_split_bytes_cjk_satzende_ohne_leerzeichen():
    t = "你好。" * 100
    parts = d._split_bytes(t, 200)
    assert len(parts) > 1 and "".join(parts) == t


def test_mymemory_gemeinsames_zeitbudget(monkeypatch):
    seen = []

    def one(p, s, t, e1, timeout):
        seen.append(timeout)
        time.sleep(0.2)
        return "x"
    monkeypatch.setattr(d, "_mymemory_one", one)
    monkeypatch.setattr(d, "_split_bytes", lambda text: ["a", "b", "c", "d"])
    d.mymemory_translate("irrelevant", "en", "de", timeout=8.0)
    assert len(seen) == 4 and seen[0] <= 8.0
    assert all(b < a - 0.1 for a, b in zip(seen, seen[1:]))          # Restzeit schrumpft, nicht je Stück neu 8 s


def test_mymemory_zeitbudget_aufgebraucht_bricht_ab(monkeypatch):
    monkeypatch.setattr(d, "_mymemory_one", lambda p, s, t, e1, timeout: time.sleep(0.6) or "x")
    monkeypatch.setattr(d, "_split_bytes", lambda text: ["a", "b", "c"])
    with pytest.raises(RuntimeError, match="Zeitbudget"):
        d.mymemory_translate("irrelevant", "en", "de", timeout=1.0)


def test_mymemory_thai_ohne_leerzeichen_zusammen(monkeypatch):
    monkeypatch.setattr(d, "_mymemory_one", lambda p, s, t, e1, timeout: "ก" if t == "th" else "k")
    monkeypatch.setattr(d, "_split_bytes", lambda text: ["a", "b"])
    assert d.mymemory_translate("x", "en", "th") == "กก"
    assert d.mymemory_translate("x", "th", "en") == "k k"


# ---- Claude: Timeout, Backoff, Kontext (E1 8-10, 12, 19, 51) ---------------------------------------------------

def test_llm_timeout_je_modell(monkeypatch):
    monkeypatch.setitem(d.LLM, "model", "claude-haiku-5-5")
    assert d.llm_timeout() == 5.0
    monkeypatch.setitem(d.LLM, "model", "claude-opus-5-5")
    assert d.llm_timeout() == 9.0


def test_claude_aufruf_bekommt_timeout(monkeypatch):
    seen = {}

    class Msgs:
        def create(self, **kw):
            seen.update(kw)
            return types.SimpleNamespace(stop_reason="end_turn", usage=None,
                                         content=[types.SimpleNamespace(type="text", text="Hallo")])
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    monkeypatch.setitem(d.LLM, "model", "claude-sonnet-5-5")
    assert d.claude_translate("hello", "en", "de") == "Hallo"
    assert seen["timeout"] == 7.0


def test_llm_backoff_wird_nicht_verkuerzt(monkeypatch):
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setitem(d.LLM, "billing_told", False)
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    now = time.monotonic()
    d._llm_failed(RuntimeError("credit balance is too low"))
    long_until = d.LLM["skip_until"]
    assert long_until >= now + d.LLM_BILLING_BACKOFF - 1
    d._llm_failed(TimeoutError("timed out"))                 # späterer kurzer Fehler (gehedgter Aufruf)
    assert d.LLM["skip_until"] == long_until


def test_llm_billing_meldung_nur_einmal(monkeypatch, ev):
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setitem(d.LLM, "billing_told", False)
    d._llm_failed(RuntimeError("credit balance is too low"))
    d._llm_failed(RuntimeError("credit balance is too low"))
    assert [e for e, _ in ev].count("error") == 1


def test_billing_meldung_nach_erfolg_wieder_moeglich(monkeypatch, ev):
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setitem(d.LLM, "billing_told", False)
    d._llm_failed(RuntimeError("credit balance is too low"))
    assert d.LLM["billing_told"] is True
    fut = types.SimpleNamespace(exception=lambda: None)
    d._llm_late(fut)                                           # verspäteter Erfolg
    assert d.LLM["billing_told"] is False
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    d._llm_failed(RuntimeError("credit balance is too low"))
    assert [e for e, _ in ev].count("error") == 2


def test_schluesseltausch_setzt_pause_zurueck(monkeypatch, ev):
    monkeypatch.setitem(d.LLM, "skip_until", time.monotonic() + 1800)
    monkeypatch.setitem(d.LLM, "err", "credit balance")
    monkeypatch.setitem(d.LLM, "on", True)
    d.apply_control(_eng(), {"llm": True})
    assert d.LLM["skip_until"] == 0.0 and d.LLM["err"] is None


def test_llm_retry_steuerfeld(monkeypatch, ev):
    monkeypatch.setitem(d.LLM, "skip_until", time.monotonic() + 600)
    monkeypatch.setitem(d.LLM, "err", "x")
    d.apply_control(_eng(), {"llm_retry": True})
    assert d.LLM["skip_until"] == 0.0 and d.LLM["err"] is None
    assert not [k for e, k in ev if e == "control_ignored"]


def test_kontext_null_schickt_keinen_verlauf(monkeypatch):
    seen = {}

    class Msgs:
        def create(self, **kw):
            seen.update(kw)
            return types.SimpleNamespace(stop_reason="end_turn", usage=None,
                                         content=[types.SimpleNamespace(type="text", text="ok")])
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    monkeypatch.setitem(d.LLM, "context", 0)
    d.claude_translate("hello", "en", "de", history=[("en", "SECRET-A", "geheim-A")])
    assert "SECRET-A" not in json.dumps(seen["messages"])


def test_spend_add_zaehlt_parallel_vollstaendig():
    ts = [threading.Thread(target=lambda: [d._spend_add(0.001) for _ in range(20)]) for _ in range(8)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert abs(d._SPEND["usd"] - 0.16) < 1e-9


def test_hedge_wird_einmal_gelesen():
    src = open(d.__file__, encoding="utf-8").read()
    assert src.count("hedge = _hedge_s()") == 1 and 'out = fut.result(timeout=_hedge_s())' not in src


# ---- Zahlen (E1 26-30) ----------------------------------------------------------------------------------------

@pytest.mark.parametrize("a,b,differ", [
    ("5th of March 2026", "5 มีนาคม 2569", False),               # buddhistisches Jahr
    ("5th of March 2026", "5 มีนาคม 2570", True),
    ("25/12/2026", "25 ธันวาคม 2026", False),                    # Monatsname = Monatsnummer
    ("about 1 hour 30 minutes", "ประมาณ 1 ชั่วโมงครึ่ง", False),
    ("one hour thirty", "หนึ่งชั่วโมงครึ่ง", False),
    ("an hour and a half", "1 ชั่วโมง 30 นาที", False),
    ("It costs a hundred baht", "ราคา 200 บาท", True),            # früher unbemerkt
    ("It costs a hundred baht", "ราคา 100 บาท", False),
    ("half a million baht", "500000 บาท", False),
    ("It costs a thousand", "ราคาหนึ่งพันบาท", False),
    # Gleichwertigkeitsregeln (Monat, Halbstunde) melden nie allein: fremde Sprache/Kurzform bleibt unauffällig
    ("am 25. Dezember", "25 ธันวาคม", False),
    ("on December 25", "25 ธ.ค.", False),
    ("It takes two and a half hours", "ใช้เวลาสองชั่วโมงครึ่ง", False),
    ("on December 25", "26 ธันวาคม", True),                     # echte Abweichung bleibt gemeldet
])
def test_zahlenpruefung_runde7(a, b, differ):
    assert d.numbers_differ(a, b) is differ


def test_fix_thai_laesst_chantha_woerter():
    out = d.fix_thai("ฉันทามติ ฉันหิว", "krub")
    assert "ฉันทามติ" in out and "ผมหิว" in out


# ---- Cache, Sätze, Glossar (E1 17, 22, 36) ---------------------------------------------------------------------

def test_norm_vereinheitlicht_apostroph():
    assert d._norm("It’s fine") == d._norm("It's fine")
    assert d._norm("“Hi”") == d._norm('"Hi"')


def test_split_sentences_hindi_und_arabisch():
    hi = "यह पहला वाक्य है जो काफी लंबा है। यह दूसरा वाक्य है जो भी लंबा है। तीसरा वाक्य यहां है।"
    assert len(d.split_sentences(hi, "hi")) >= 2
    ar = "هذه هي الجملة الأولى الطويلة جدا؟ وهذه هي الجملة الثانية الطويلة جدا؛ والثالثة هنا الآن."
    assert len(d.split_sentences(ar, "ar")) >= 2


def test_glossar_wortgrenze_mit_akzent():
    assert d._term_rx("Éric").search("Frédéric") is None
    assert d._term_rx("Éric").search("hi Éric!")
    assert d._term_rx("Pat").search("ผมชื่อPat")              # Thai davor ist keine Wortgrenze
    assert d._term_rx("Pat").search("path") is None


# ---- Lachen, Füllwörter, Floskeln (E1 33-35, 47) -----------------------------------------------------------------

def test_lachwort_mitten_im_satz_bleibt():
    rx = d.LAUGH["en"]
    assert d._strip_edge_laugh(rx, "I said lol and left") == "I said lol and left"
    assert d._strip_edge_laugh(rx, "that was great lol") == "that was great"
    assert d._strip_edge_laugh(rx, "haha") == ""


@pytest.mark.parametrize("lang,text,want", [("de", "hahaha", True), ("zh", "哈哈。", True), ("ko", "ㅋㅋㅋ", True),
                                            ("ja", "wwww", True), ("es", "jajaja", True), ("de", "Hallo", False)])
def test_lachen_weitere_sprachen(lang, text, want):
    assert bool(d.LAUGH[lang].search(text)) is want
    assert d.LAUGH_OUT[lang]


@pytest.mark.parametrize("lang,text,want", [("de", "Äh, ich möchte ähm ein Bier", "ich möchte ein Bier"),
                                            ("ja", "えーと、トイレはどこですか", "トイレはどこですか"),
                                            ("de", "Hähnchen bitte", "Hähnchen bitte")])
def test_fuellwoerter_weitere_sprachen(lang, text, want):
    assert d.strip_fillers(text, lang) == want


def test_abspann_floskeln_weitere_sprachen():
    assert "Vielen Dank fürs Zuschauen!" in d.JUNK and "谢谢观看" in d.JUNK
    assert d.junk_by("Субтитры сделал DimaTorzok")
    assert "ich bin dankbar" not in d.JUNK


# ---- Steuerfelder (E2 3, 4, 5, 39, 40, 61) --------------------------------------------------------------------------

@pytest.mark.parametrize("key,val", [("sensitivity", [1]), ("style", {}), ("catch_up", []), ("lang", {"a": 1}),
                                     ("polite", [None]), ("sensitivity", "nonsense")])
def test_unhashable_und_ungueltige_werte_werfen_nicht(ev, key, val):
    e = _eng()
    d.apply_control(e, {key: val, "rate": 5})
    assert e.rate == 5                                       # Rest der Zeile geht nicht verloren
    assert ("control_invalid", {"key": key, "reason": "value"}) in ev


def test_gueltige_werte_ohne_control_invalid(ev):
    e = _eng()
    d.apply_control(e, {"sensitivity": "high", "style": "polite", "polite": "ka", "lang": "th"})
    assert e.polite == "ka" and e.lock == "th" and not [x for x in ev if x[0] == "control_invalid"]


def test_unbekannte_stimme_behaelt_bisherige(ev):
    e = _eng(voices={"en": "en-US-GuyNeural", "th": None})
    d.apply_control(e, {"voice_en": "Tippfehler"})
    assert e.voices["en"] == "en-US-GuyNeural"
    assert [x for x in ev if x[0] == "error" and x[1]["code"] == "voice_unknown"]


def test_history_days_allein_wird_angewendet(monkeypatch, tmp_path, ev):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    rec = hs.Recorder()
    monkeypatch.setattr(hs, "RECORDER", rec)
    d.apply_control(_eng(), {"history_days": 30})
    assert rec.keep_days == 30.0
    d.apply_control(_eng(), {"history_days": 0})
    assert rec.keep_days is None


def test_listen_vor_mikrofon_geht_nicht_verloren(monkeypatch, ev):
    monkeypatch.setattr(d, "MIC", None)
    monkeypatch.setitem(d.MIC_PENDING, "listen", None)
    d.apply_control(_eng(), {"listen": True})
    assert d.MIC_PENDING["listen"] is True
    d.MIC_PENDING["listen"] = None


def test_steuerzeile_obergrenze_dokumentiert():
    assert d.CTRL_LINE_MAX >= d.GLOSSARY_MAX


# ---- clear (Mac-Punkt 9) und Aufhol-Modus (E2 1, 38) ---------------------------------------------------------------

class _FakeSpeaker:
    def __init__(self):
        self.flushed = 0

    def flush(self):
        self.flushed += 1


def test_clear_steuerfeld_leert_kontext_und_ausgabe(monkeypatch, ev):
    e = d.Engine.__new__(d.Engine)
    e.history = collections.deque([("en", "a", "b")])
    e.last = ("x", "en", "u1")
    e.texts, e.recent, e._hist_ids = {"u1": 1}, {"u1": 1}, {"u1": 1}
    e.speaker = _FakeSpeaker()
    d._cache_put(("k",), ("v", "claude"))
    jobs = d.apply_control(e, {"clear": True})
    assert jobs is None
    assert not e.history and e.last is None and not e.texts and not e.recent and not e._hist_ids
    assert d._cache_get(("k",)) is None and e.speaker.flushed == 1
    assert ("cleared", {}) in ev


def test_speaker_pin_wird_gemerkt_und_nie_uebersprungen():
    sp = d.Speaker.__new__(d.Speaker)
    sp.eng = types.SimpleNamespace(mute=False, tts="say", rate=0)
    sp.items, sp.cond, sp.busy = collections.deque(), threading.Condition(), False
    sp.add("", "en", "cmd", kind="earcon", pin=True)
    assert sp.items[0]["pin"] is True
    src = open(d.__file__, encoding="utf-8").read()
    assert 'not SLOW["on"] and not it.get("pin")' in src


def test_katalog_schnellsatz_und_nochmal_sprechen_gepinnt():
    src = open(d.__file__, encoding="utf-8").read()
    assert 'self.speaker.add(self.last[0], self.last[1], "cmd", pin=True)' in src
    assert 'self.speaker.add(text, lang, uid or new_id(), pin=True)' in src
    assert 'pin=source in ("phrase", "edit")' in src


# ---- Warteschlange, Überlauf (E2 12, 13, 15) ---------------------------------------------------------------------

def test_work_queue_begrenzt_aelteste_aeusserung(monkeypatch, ev):
    q = d.WorkQueue()
    for i in range(d.WorkQueue.MAX_UTTS + 5):
        q.put((np.zeros(3), 0.1, 0, "x", 0, 0, f"u{i}"))
    q.put(("job", lambda: None))
    q.put(("pre", "u99", 1, np.zeros(2)))
    utts = [x for x in q.queue if not isinstance(x[0], str)]
    assert len(utts) == d.WorkQueue.MAX_UTTS and utts[0][6] == "u5"
    dropped = [k for e, k in ev if e == "dropped"]
    assert [k["id"] for k in dropped] == [f"u{i}" for i in range(5)] and dropped[0]["code"] == "backlog"
    assert len(q.jobs) == 1


def test_overrun_wird_gezaehlt_und_selten_gemeldet(monkeypatch, ev):
    monkeypatch.setattr(d, "_OVERRUN", {"n": 0, "t": 0.0, "told": 0})
    for _ in range(50):
        d._note_overrun()
    assert d._OVERRUN["n"] == 50
    assert len([e for e, _ in ev if e == "overrun"]) == 1


def test_dropped_bei_fehler_hat_code():
    assert 'emit("dropped", reason="fehler", code="error", id=uid)' in open(d.__file__, encoding="utf-8").read()


# ---- Neuerkennung "Das war ich/sie" (E2 9, 10) -------------------------------------------------------------------

def test_reassign_filter_wie_process():
    audio = np.zeros(16000 * 2, dtype=np.float32)
    assert d.Engine._clean_reassigned("Thank you for watching", audio, [], "en") == ""
    assert d.Engine._clean_reassigned("", audio, [], "en") == ""
    assert d.Engine._clean_reassigned("hello there", audio, [], "en") == "hello there"


def test_reassign_lernt_erst_nach_erfolg(monkeypatch, ev):
    learned = []
    spk = types.SimpleNamespace(me=lambda: {"name": "Me"}, partner=lambda: {"name": "Her"},
                                embed=lambda a: np.ones(2), learn=lambda *a: learned.append(a) or True)
    e = d.Engine.__new__(d.Engine)
    e.spk, e.history, e.last_role = spk, collections.deque(), None
    audio = np.zeros(16000 * 3, dtype=np.float32)
    e.recent = collections.OrderedDict(u1=(audio, None))
    e.__dict__["_recent_t"] = {"u1": time.monotonic()}
    monkeypatch.setattr(e, "_stt", lambda a, lg, hotwords=None: ("", -0.5, []), raising=False)
    monkeypatch.setattr(e, "_hotwords", lambda *a, **k: None, raising=False)
    e.reassign("u1", "me")
    assert learned == []                                       # nichts erkannt: Stimmabdruck bleibt
    assert [k for e_, k in ev if e_ == "error" and k["code"] == "reassign_empty"]


# ---- Verbindungspool, Captive Portal (E1 6, 7) ---------------------------------------------------------------------

class _Conn:
    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True


def test_pool_verwirft_alte_verbindungen():
    ka = d.KeepAlive()
    old, fresh = _Conn(), _Conn()
    old._dm_t = time.monotonic() - ka.IDLE_MAX_S - 5
    fresh._dm_t = time.monotonic()
    ka.idle["h"] = [fresh, old]                                # old liegt obenauf (wird zuerst genommen)
    c, reused = ka._take("h", 5)
    assert c is fresh and reused and old.closed


def test_pool_give_stempelt_einstelldatum():
    ka = d.KeepAlive()
    c = _Conn()
    ka._give("h", c)
    assert time.monotonic() - c._dm_t < 1


def test_captive_portal_wird_gemeldet_und_pausiert(monkeypatch, ev):
    monkeypatch.setattr(d, "_CAPTIVE", {"t": -1e9})
    d._note_fail("google", d.NotJSON("html"))
    d._note_fail("google", d.NotJSON("html"))
    assert len([k for e, k in ev if e == "captive_portal"]) == 1
    assert d._PROV["google"]["until"] > time.monotonic()
    d.reset_net_backoff()
    d._note_fail("mymemory", urllib.error.HTTPError("u", 302, "Found", {}, None))
    assert d._PROV["mymemory"]["until"] > time.monotonic()


# ---- macOS-Stimmenliste, Pseudonym, Rosetta (E1 43, E2 16, 41) ---

def test_say_voices_fehlschlag_wird_gemerkt(monkeypatch):
    calls = []

    def boom(*a, **k):
        calls.append(1)
        raise OSError("kein say")
    monkeypatch.setattr(d.subprocess, "run", boom)
    monkeypatch.setattr(d, "_SAY_LIST", {"out": None, "fail_t": None})
    assert d._say_voices() == "" and d._say_voices() == "" and len(calls) == 1


def test_pseudonym_gesalzen(monkeypatch, tmp_path):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    monkeypatch.setattr(d, "_PSEUD_SALT", {"v": None})
    a = d._pseud("Patrick")
    assert a == d._pseud("Patrick") and "Patrick" not in a
    import hashlib
    assert a != "p-" + hashlib.sha256(b"Patrick").hexdigest()[:6]
    assert (tmp_path / "log_salt").exists() and stat.S_IMODE((tmp_path / "log_salt").stat().st_mode) == 0o600


def test_rosetta_wird_als_arm_erkannt():
    def run(cmd, **kw):
        v = {"hw.memsize": str(16 * 2 ** 30), "machdep.cpu.brand_string": "Apple M2",
             "hw.optional.arm64": "1"}.get(cmd[-1])
        return types.SimpleNamespace(returncode=0 if v is not None else 1, stdout=v or "")
    assert hwprofile.detect(run, "x86_64")["arm64"] is True
    assert hwprofile.auto_choice(run, "x86_64")["model"] == "medium"


def test_ids_haben_laufkennzeichen():
    a = d.new_id()
    assert a.startswith("u") and "-" in a and a != d.new_id()


# ---- Stimmprofil mit --mic/--denoise (Mac-Punkt) ---

def test_record_one_reicht_denoise_weiter(monkeypatch):
    seen = {}
    monkeypatch.setattr(d, "resolve_mic", lambda m: m)
    monkeypatch.setattr(d, "capture_cmd", lambda dev=None, af=None, **k: seen.update(af=af, dev=dev) or ["x"])

    def stop(*a, **k):
        raise KeyboardInterrupt
    monkeypatch.setattr(d.subprocess, "Popen", stop)
    with pytest.raises(KeyboardInterrupt):
        d.record_one("3", denoise=True)
    assert "afftdn" in seen["af"] and seen["dev"] == "3"
    with pytest.raises(KeyboardInterrupt):
        d.record_one("3")
    assert "afftdn" not in seen["af"]


def test_profile_stdin_kennt_mic_und_denoise():
    src = open(d.__file__, encoding="utf-8").read()
    assert 'req.get("mic")' in src or 'req["mic"]' in src
    assert 'req.get("denoise")' in src or 'req["denoise"]' in src


# ---- Verlauf (E2 18-26) ---

def _store(tmp_path):
    return hs.Store(str(tmp_path / "h.sqlite"))


def test_csv_formelinjektion_wird_entschaerft(tmp_path):
    st = _store(tmp_path)
    st.add("=1+1", "+cmd|calc", lang="en", session="s")
    st.add("normal", "-5", lang="en", session="s")
    out = hs.export(st.rows(), "csv")
    assert "'=1+1" in out and "'+cmd|calc" in out and "'-5" in out and "\n=1+1" not in out
    st.close()


def test_srt_leerzeile_im_text_zerbricht_cue_nicht(tmp_path):
    st = _store(tmp_path)
    st.add("eins\n\nzwei", "one\n\ntwo", lang="en", session="s", ts=1000.0)
    out = hs.export(st.rows(), "srt")
    cue = out.strip().split("\n")
    assert cue[0] == "1" and "\n\n" not in out.strip() and "eins zwei" in out and "one two" in out
    st.close()


def test_suche_mit_vielen_treffern_ohne_variablengrenze(tmp_path):
    st = _store(tmp_path)
    with st.db:
        for i in range(34000):
            st.db.execute("INSERT INTO utt (uid, ts, session, lang, text, translation) VALUES (?,?,?,?,?,?)",
                          (str(i), 1.0 + i, "s", "en", "häufig", "t"))
            if st.fts:
                st.db.execute("INSERT INTO utt_fts (rowid, text, translation) VALUES (last_insert_rowid(), ?, ?)",
                              ("häufig", "t"))
    assert len(st.search("häufig", limit=5)) == 5
    st.close()


def test_vorhandener_ordner_behaelt_rechte(tmp_path):
    os.chmod(tmp_path, 0o755)
    hs.Store(str(tmp_path / "x.sqlite")).close()
    assert stat.S_IMODE(tmp_path.stat().st_mode) == 0o755
    fresh = tmp_path / "neu"
    hs.Store(str(fresh / "x.sqlite")).close()
    assert stat.S_IMODE(fresh.stat().st_mode) == 0o700


def test_out_datei_bekommt_0600(tmp_path):
    out = tmp_path / "e.md"
    out.write_text("alt")
    os.chmod(out, 0o644)
    a = types.SimpleNamespace(history_export="md", history_session=None, out=str(out), history_search=None,
                              history_purge=None, history_clear=False, history_sessions=False)
    import contextlib
    import io
    with contextlib.redirect_stdout(io.StringIO()):
        hs_home = tmp_path / "home"
        os.environ["DOLMETSCHER_HOME"] = str(hs_home)
        try:
            assert hs.run_cli(a) == 0
        finally:
            del os.environ["DOLMETSCHER_HOME"]
    assert stat.S_IMODE(out.stat().st_mode) == 0o600


def test_recorder_sperre_schaltet_nicht_sofort_ab(tmp_path):
    import sqlite3
    rec = hs.Recorder()
    rec.on = True

    def locked(*a, **k):
        raise sqlite3.OperationalError("database is locked")
    rec.store = types.SimpleNamespace(add=locked, purge=lambda days: 0)
    for _ in range(hs.Recorder.MAX_FAILS - 1):
        rec.utt({"text": "x"})
        assert rec.on                                           # vorübergehend: Zeile fehlt, Aufzeichnung bleibt
    errs = []
    rec.on_error = lambda: errs.append(1)
    rec.utt({"text": "x"})
    assert not rec.on and errs == [1]


def test_recorder_anderer_fehler_schaltet_sofort_ab():
    rec = hs.Recorder()
    rec.on = True
    rec.store = types.SimpleNamespace(add=lambda *a, **k: 1 / 0, purge=lambda d_: 0)
    rec.utt({"text": "x"})
    assert not rec.on


def test_recorder_neue_sitzung_nach_pause_und_stuendliches_purge():
    rec = hs.Recorder()
    purged = []
    rec.store = types.SimpleNamespace(purge=lambda days: purged.append(days) or 0)
    rec.keep_days = 7.0
    first = rec.session
    rec._roll(1_000_000.0)
    rec._purge_thread.join(5)
    assert rec.session == first and purged == [7.0]
    rec._roll(1_000_000.0 + 60)
    assert rec.session == first
    rec._roll(1_000_000.0 + 60 + hs.Recorder.SESSION_GAP_S + 10)
    assert rec.session != first
    rec.last_purge = time.monotonic() - hs.Recorder.PURGE_EVERY_S - 1
    rec._roll(1_000_000.0 + 60 + hs.Recorder.SESSION_GAP_S + 20)
    rec._purge_thread.join(5)
    assert len(purged) == 2


def test_history_sessions_cli(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    st = hs.Store()
    st.add("a", "b", lang="en", session="s1", ts=5.0)
    st.add("c", "d", lang="en", session="s1", ts=6.0)
    st.close()
    a = types.SimpleNamespace(history_export=None, history_session=None, out=None, history_search=None,
                              history_purge=None, history_clear=False, history_sessions=True)
    assert hs.wants_cli(a)
    assert hs.run_cli(a) == 0
    rows = json.loads(capsys.readouterr().out)
    assert rows[0]["id"] == "s1" and rows[0]["count"] == 2


# ---- Presets (E2 27, 28, 52) ---

def _preset(**kw):
    p = {"id": "t", "names": {"de": "T", "en": "T", "th": "T"}, "style": "polite", "polite": "ka",
         "voice": {"en": "en-US-AriaNeural", "th": "th-TH-Falsch"}}
    p.update(kw)
    return p


def test_preset_stimme_wird_gegen_liste_geprueft():
    st, e = P.PresetState(), _eng()
    llm = {"style": "casual"}
    st.activate("t", {"t": _preset()}, [], llm, e, voices={"en": ["en-US-AriaNeural"], "th": ["th-TH-PremwadeeNeural"]})
    assert e.voices["en"] == "en-US-AriaNeural" and e.voices["th"] is None


def test_preset_ende_ueberschreibt_nutzerwahl_nicht():
    st, e = P.PresetState(), _eng(voices={"en": "alt", "th": None})
    llm = {"style": "casual"}
    st.activate("t", {"t": _preset()}, [], llm, e)
    assert e.polite == "ka" and llm["style"] == "polite"
    e.polite, e.voices["en"] = "krub", "meine-stimme"          # Nutzer ändert währenddessen
    st.activate(None, {"t": _preset()}, [], llm, e)
    assert e.polite == "krub" and e.voices["en"] == "meine-stimme"
    assert llm["style"] == "casual"                              # unverändert -> zurück auf den Stand davor


def test_preset_ende_stellt_unveraenderte_felder_wieder_her():
    st, e = P.PresetState(), _eng(voices={"en": "alt", "th": None})
    llm = {"style": "casual"}
    st.activate("t", {"t": _preset()}, [], llm, e)
    st.activate(None, {"t": _preset()}, [], llm, e)
    assert e.polite == "krub" and e.voices["en"] == "alt" and llm["style"] == "casual"


def test_load_all_cache_und_aenderung(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    app = tmp_path / "app"
    app.mkdir()
    monkeypatch.setattr(P, "app_dir", lambda: str(app))
    (app / "a.json").write_text(json.dumps(_preset(id="a", voice={})), encoding="utf-8")
    first = P.load_all()
    assert "a" in first
    calls = []
    orig = P._load_all_uncached
    monkeypatch.setattr(P, "_load_all_uncached", lambda: calls.append(1) or orig())
    assert "a" in P.load_all() and calls == []                  # Treffer aus dem Zwischenspeicher
    (app / "b.json").write_text(json.dumps(_preset(id="b", voice={})), encoding="utf-8")
    assert {"a", "b"} <= set(P.load_all()) and calls == [1]


# ---- Korrektur-Lernen (E2 29-31) ---

def test_korrektur_lernen_kyrillisch_und_japanisch():
    assert cl.suggest_vocab("я иду в клиник", "я иду в клинику", "ru") == ["клинику"]
    assert cl.suggest_vocab("病院に行きます", "大学病院に行きます", "ja") == ["大学"]
    assert cl.suggest_vocab("مرحبا بك", "مرحبا بكم في المطار", "ar") == ["بكم", "المطار"]


def test_deutsche_substantive_sind_keine_eigennamen():
    assert cl.proper_names("wir gehen", "Wir gehen zum Bahnhof Berlin", "de") == []


# ---- avhelper, profiles (E2 42, 43, 50, 59, 35) ---

def test_avhelper_weicher_begrenzer():
    import avhelper
    x = np.array([0.5, 0.9, -1.0, 0.2], dtype=np.float32)
    y = avhelper._soft_limit(x, 2.0)
    assert np.all(np.abs(y) <= 1.0) and abs(y[3] - 0.4) < 1e-6 and y[1] < 1.0 and y[1] > 0.9
    assert np.array_equal(avhelper._soft_limit(x, 1.0), x)


def test_avhelper_ohne_tonspur_klare_meldung():
    src = open(os.path.join(os.path.dirname(d.__file__), "avhelper.py"), encoding="utf-8").read()
    assert src.count('sys.exit("no audio stream")') == 2 and "rs.resample(None)" in src


def test_hotwords_nach_schrift_statt_profilsprache():
    en = {"name": "E", "lang": "en", "vocab": ["Patong", "ภูเก็ต"]}
    th = {"name": "T", "lang": "th", "vocab": ["Karon", "ตลาด"]}
    got = set(profiles.pick_hotwords([en, th], "th").split())
    assert "ภูเก็ต" in got and "ตลาด" in got and "Patong" not in got    # Thai-Wort aus dem EN-Profil hilft Thai
    got_en = set(profiles.pick_hotwords([en, th], "en").split())
    assert {"Patong", "Karon"} <= got_en and "ตลาด" not in got_en       # Latein aus dem TH-Profil hilft Englisch


def test_sprechermodell_wird_geprueft(tmp_path, monkeypatch):
    import hashlib
    data = b"modell" * 100
    monkeypatch.setattr(profiles, "MODEL_PATH", str(tmp_path / "m" / "model.onnx"))
    monkeypatch.setattr(profiles, "MODEL_SHA256", hashlib.sha256(data).hexdigest())
    (tmp_path / "m").mkdir()
    open(profiles.MODEL_PATH, "wb").write(data)
    assert profiles._model_ok() and os.path.exists(profiles.MODEL_PATH + ".ok")
    assert profiles._model_ok()                                  # zweites Mal über den Stempel
    open(profiles.MODEL_PATH, "wb").write(data[:50])             # abgeschnitten
    assert not profiles._model_ok()


def test_quarantaene_meldung_ohne_profilnamen(tmp_path, capsys):
    p = tmp_path / "Patrick.json"
    p.write_text("{kaputt")
    profiles._quarantine(str(p), "kein JSON")
    assert "Patrick" not in capsys.readouterr().err and "Patrick" not in profiles.CORRUPT[-1]


# ---- languages.json fehlerhaft (E1 42) ---

def test_kaputte_sprachtabelle_gibt_json_fehler(monkeypatch, capsys):
    def kaputt(path=None):
        raise KeyError("names")
    monkeypatch.setattr(d, "load_lang_table", kaputt)
    with pytest.raises(SystemExit) as ex:
        d._load_lang_table_or_exit()
    assert ex.value.code == 4
    line = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert line["event"] == "error" and line["code"] == "languages_invalid" and "names" in line["msg"]


# ---- LocalVoice: halbe Datei nie abspielen (E2 6) ---

def test_local_voice_zeitueberschreitung_loescht_datei(monkeypatch, tmp_path):
    monkeypatch.setattr(d, "private_tmp", lambda: str(tmp_path))
    monkeypatch.setattr(d, "say_cmd", lambda voice, rate, path, text: ["x", path])

    def fake_run(cmd, cancelled=None):
        open(cmd[1], "wb").write(b"halb")                        # halb geschrieben, dann Zeitüberschreitung
        return None
    monkeypatch.setattr(d, "run_cancellable", fake_run)
    lv = d.LocalVoice("hi", "Samantha", 0)
    assert lv.done.wait(5)
    assert lv.ready_path(timeout=0.5) is None and not os.path.exists(lv.path)
