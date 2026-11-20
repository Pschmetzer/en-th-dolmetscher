"""Runde 2 (Ideenliste): Thai-Uhrzeiten im Prompt (13), Claude-Monatslimit (16), Vorab-Erkennung mit
Hotwords (157), Glossar-Hotwords (160), Mikrofonwechsel live (158), Ereignis `missed` (159),
`dropped` mit Text bei Übersetzungsfehler (161)."""
import json
import queue
import types

import numpy as np
import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


# --- 13: Thai-Uhrzeiten ------------------------------------------------------------------------------

def test_prompt_hat_thai_zeitregeln_auch_fuer_andere_paare(monkeypatch):
    assert "สองทุ่ม" in d.LLM_SYSTEM and "ตีสาม" in d.LLM_SYSTEM
    assert "English" not in d.THAI_TIME_RULES          # sonst verbiegt llm_system() den Text für de/th
    monkeypatch.setattr(d, "PAIR", ["de", "th"])
    s = d.llm_system(("de", "th"))
    assert d.THAI_TIME_RULES in s and "German" in s
    assert d.THAI_TIME_RULES not in d.llm_system(("de", "es"))


# --- 16: Monatslimit ---------------------------------------------------------------------------------

def test_monatslimit_schaltet_auf_google_und_meldet_einmal(ev, monkeypatch):
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    called = []
    monkeypatch.setattr(d, "_claude_async", lambda *a: called.append("claude"))
    monkeypatch.setattr(d, "_mt_chain", lambda text, src, dst, meta, deadline=None:
                        meta.update(provider="google") or "hallo")
    d.LLM["budget"] = 1.0
    d._spend_add(1.5)
    assert d._translate("hello", "en", "de") == "hallo" and not called
    d._translate("hello again", "en", "de")
    errs = [kw for e, kw in ev if e == "error"]
    assert [e["code"] for e in errs] == ["llm_budget"]


def test_monatskosten_ueberleben_neustart_und_monatswechsel(monkeypatch):
    d._spend_add(0.25)
    saved = json.load(open(d.LLM_SPEND_FILE))
    assert saved["usd"] == 0.25 and saved["month"] == d._month()
    d._SPEND.update(month=None, usd=0.0)                # „Neustart“
    assert d.llm_month_usd() == 0.25
    monkeypatch.setattr(d, "_month", lambda: "2099-01")
    assert d.llm_month_usd() == 0.0                     # neuer Monat: von vorn


def test_ohne_limit_kein_stopp():
    d._spend_add(99.0)
    assert d.LLM["budget"] == 0.0 and not d.llm_over_budget()


def test_steuerfeld_llm_budget(ev):
    eng = types.SimpleNamespace()
    d.apply_control(eng, {"llm_budget": 5})
    assert d.LLM["budget"] == 5.0
    d.apply_control(eng, {"llm_budget": "viel"})
    assert d.LLM["budget"] == 5.0


# --- 157/160: Hotwords ------------------------------------------------------------------------------

def test_glossar_hotwords_nach_schrift(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Somchai", None), ("Hotel", "โรงแรม"), ("ตลาดน้ำ", "floating market")])
    assert d.glossary_hotwords("en") == ["Somchai", "Hotel", "floating market"]
    assert d.glossary_hotwords("th") == ["โรงแรม", "ตลาดน้ำ"]
    assert d.merge_hotwords("Somchai Pattaya", ["somchai", "Hotel"]) == "Somchai Pattaya Hotel"
    assert d.merge_hotwords(None, []) is None
    long = ["w%03d" % i for i in range(200)]
    assert len(d.merge_hotwords(None, long)) <= d.HOTWORDS_MAX_CHARS
    assert d.hotword_key("A b") == d.hotword_key("B a") and d.hotword_key(None) is None


def _engine(calls, spk=None):
    class Det:
        def detect_language(self, audio=None, language_detection_segments=2):
            calls.append("detect")
            return "en", 0.95, [("en", 0.95), ("de", 0.02)]
    e = d.Engine.__new__(d.Engine)
    e.m_det, e.spk, e.lock, e.paused, e.awake_until = Det(), spk, "auto", False, 0.0
    e.translate_dir = {"en": True, "th": True}

    def fake_stt(audio, lang, hotwords=None, model=None, quick=False):
        calls.append(("stt", lang, hotwords))
        return "Where is the station?", -0.2, [types.SimpleNamespace(compression_ratio=1.1)]
    e._stt = fake_stt
    e.deliver = lambda uid, lang, text, *a, **k: calls.append(("deliver", uid, text)) or (lang, text, "x")
    return e


def test_vorab_erkennung_mit_glossar_hotwords_wird_wiederverwendet(monkeypatch):
    monkeypatch.setitem(d.FAST, "endpoint", False)
    monkeypatch.setattr(d, "GLOSSARY", [("Somchai", None)])
    calls = []
    e = _engine(calls)
    audio = np.full(d.SR * 2, 0.05, dtype=np.float32)
    e.prerecognize("g1", 0, audio)
    assert ("stt", "en", "Somchai") in calls
    n = len(calls)
    e.process(audio, speak=False, uid="g1", version=0)
    assert calls[n:] == [("deliver", "g1", "Where is the station?")]    # keine zweite Erkennung


def test_vorab_erkennung_mit_profil_hotwords_trotz_anderer_reihenfolge(monkeypatch):
    """Erkanntes Profil steht in process() vorn – die Wörter sind dieselben, also wiederverwenden."""
    monkeypatch.setitem(d.FAST, "endpoint", False)
    monkeypatch.setattr(d, "GLOSSARY", [])
    me = {"name": "Pat", "lang": "en", "vocab": ["Korat"]}
    other = {"name": "Joy", "lang": "en", "vocab": ["Isaan"]}

    class Spk:
        def lazy_embed(self, audio):
            return lambda: None

        def identify(self, audio, emb=None):
            return other, 0.9, {"Joy": 0.9}

        def hotwords(self, lng, who=None, role=None):
            order = [who] if who else []
            return " ".join(w for p in order + [p for p in (me, other) if p is not who] for w in p["vocab"])
    calls = []
    e = _engine(calls, Spk())
    audio = np.full(d.SR * 2, 0.05, dtype=np.float32)
    e.prerecognize("p1", 0, audio)
    assert ("stt", "en", "Korat Isaan") in calls
    n = len(calls)
    e.process(audio, speak=False, uid="p1", version=0)
    assert not [c for c in calls[n:] if isinstance(c, tuple) and c[0] == "stt"]


# --- 158: Mikrofonwechsel ---------------------------------------------------------------------------

def test_steuerfeld_mic_vor_dem_laden_und_ungueltig(ev, monkeypatch):
    monkeypatch.setattr(d, "MIC", None)
    monkeypatch.setattr(d, "MIC_PENDING", {"mic": None})
    eng = types.SimpleNamespace()
    assert d.apply_control(eng, {"mic": "USB Mic"}) is None
    assert d.MIC_PENDING["mic"] == "USB Mic"
    d.apply_control(eng, {"mic": True})
    assert [kw["code"] for e, kw in ev if e == "error"] == ["mic_invalid"]


def test_steuerfeld_mic_wechselt_live(ev, monkeypatch):
    m = d.Mic(types.SimpleNamespace(stop_speaking=lambda: None), "0", queue.Queue(), idle=True)
    killed, started = [], []
    monkeypatch.setattr(d.Mic, "_kill", staticmethod(lambda ff: killed.append(ff)))
    monkeypatch.setattr(m, "start", lambda **kw: started.append(m.mic) or True)
    monkeypatch.setattr(d, "MIC", m)
    job = d.apply_control(types.SimpleNamespace(), {"mic": "AirPods"})
    assert job is not None and m.mic == "0"            # Wechsel läuft im Arbeits-Thread
    job()
    assert m.mic == "AirPods" and not started          # Mikrofon war aus: nur merken
    m.on, m.ff, sess = True, "FF", m.sess
    d.apply_control(types.SimpleNamespace(), {"mic": 2})()
    assert killed == ["FF"] and started == ["2"] and m.sess == sess + 1
    assert not [e for e, kw in ev if e == "mic" and kw.get("on") is False]   # kein Aus-Flackern


def test_mic_und_say_in_einer_zeile_laufen_beide(monkeypatch):
    m = d.Mic(types.SimpleNamespace(), "0", queue.Queue(), idle=True)
    monkeypatch.setattr(d, "MIC", m)
    said = []
    eng = types.SimpleNamespace(say_phrase=lambda t, lang: said.append(t))
    d.apply_control(eng, {"mic": "X", "say": {"text": "hi", "lang": d.PAIR[0]}})()
    assert m.mic == "X" and said == ["hi"]


# --- 159: missed -------------------------------------------------------------------------------------

class _FakeVAD:
    N, CTX = 512, 64

    def __init__(self, probs):
        self.probs = iter(probs)

    def reset(self):
        pass

    def __call__(self, f):
        return next(self.probs, 0.0)


def _segment(monkeypatch, probs, gate):
    """probs: VAD je ungesperrtem Frame; gate: Frame-Indizes, in denen die eigene Ausgabe läuft."""
    monkeypatch.setattr(d, "StreamVAD", lambda: _FakeVAD(probs))
    monkeypatch.setattr(d.StreamVAD, "N", 512, raising=False)
    monkeypatch.setitem(d.FAST, "pre", False)
    monkeypatch.setattr(d, "BARGE_IN", False)
    n = len(probs) + len(gate)
    t0, fd = 1000.0, 512 / d.SR
    gated = {round(t0 + i * fd, 6) for i in gate}
    monkeypatch.setattr(d.PLAYER, "gated", lambda t: round(t, 6) in gated)
    frames = queue.Queue()
    for i in range(n):
        frames.put((np.full(512, 0.1, dtype=np.float32), t0 + i * fd))
    frames.put((np.zeros(0, dtype=np.float32), 0.0))
    d.segmenter(frames.get, queue.Queue())


def test_missed_wenn_ausgabe_mitten_im_satz_beginnt(ev, monkeypatch):
    _segment(monkeypatch, [0.9] * 20 + [0.0] * 40, gate=range(20, 50))
    m = [kw for e, kw in ev if e == "missed"]
    assert len(m) == 1 and m[0]["why"] == "cut" and m[0]["dur"] > 0.5


def test_missed_wenn_direkt_nach_ausgabe_gesprochen_wird(ev, monkeypatch):
    _segment(monkeypatch, [0.0] * 5 + [0.9] * 3 + [0.0] * 30, gate=range(5, 35))
    m = [kw for e, kw in ev if e == "missed"]
    assert len(m) == 1 and m[0]["why"] == "overlap"


def test_kein_missed_bei_stille_nach_ausgabe(ev, monkeypatch):
    _segment(monkeypatch, [0.0] * 40, gate=range(5, 35))
    assert not [e for e, kw in ev if e == "missed"]


# --- 161: dropped mit Text ----------------------------------------------------------------------------

def test_uebersetzungsfehler_meldet_text_und_sprache(ev, monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("offline – keine Internetverbindung")
    monkeypatch.setattr(d, "translate", boom)
    e = d.Engine.__new__(d.Engine)
    e.texts, e.history, e.translate_dir, e.polite = {}, [], {}, "krub"
    assert e.deliver("u5", "en", "Where is it?", speak=False) is None
    drop = [kw for x, kw in ev if x == "dropped"][0]
    assert drop["code"] == "translate_failed" and drop["text"] == "Where is it?" and drop["lang"] == "en"
