"""Engine-Pipeline: heard, Korrekturen (history/last/recent), dropped-Codes, Befehle nur von mir,
Wake-Fenster ab speak_done, Arbeits-Warteschlange, Segmentierer, normalize, Mikrofon-Helfer."""
import collections
import queue
import subprocess
import types

import numpy as np
import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    monkeypatch.setitem(d.LLM, "on", False)
    return events


def _engine(probs, texts, role=None):
    class Det:
        def detect_language(self, audio=None, language_detection_segments=2):
            return probs[0][0], probs[0][1], probs

    class Spk:
        profiles = []

        def lazy_embed(self, a):
            return lambda: None

        def identify(self, a, emb=None):
            return None, 0.0, {}

        def classify(self, a, prev=None, emb=None):
            return {"role": role, "how": "vergleich", "sim_me": 0.5, "sim_her": 0.5, "emb": None}
    e = d.Engine.__new__(d.Engine)
    e.m_det, e.m, e.m_th, e.lock, e.paused, e.awake_until = Det(), None, None, "auto", False, 0.0
    e.spk, e.two_person = (Spk(), True) if role else (None, False)
    e.translate_dir = {"en": True, "th": True}
    e.history, e.texts, e.last, e.mute = collections.deque(maxlen=8), {}, None, False
    e.polite, e.rate, e.volume, e.voices, e.earcons = "krub", 0, 1.0, {}, False
    e.recent = collections.OrderedDict()
    e.speaker = types.SimpleNamespace(add=lambda *a, **k: None)
    e._stt = lambda audio, lang, hotwords=None, model=None, quick=False: (
        *texts[lang], [types.SimpleNamespace(compression_ratio=1.1)])
    return e


AUDIO = np.full(d.SR * 2, 0.05, dtype=np.float32)


def test_heard_kommt_vor_der_uebersetzung(ev, monkeypatch):
    e = _engine([("en", 0.95)], {"en": ("Where is the station?", -0.2), "th": ("x", -2.0)})
    order = []
    monkeypatch.setattr(d, "translate", lambda *a, **k: order.append("translate") or "สถานีอยู่ที่ไหน")
    e.process(AUDIO, speak=False, uid="u1")
    names = [x[0] for x in ev]
    assert names.index("thinking") < names.index("heard") < names.index("utt")
    heard = dict(ev)["heard"]
    assert heard == {"id": "u1", "lang": "en", "text": "Where is the station?", "text_latin": None}


def test_unsicher_liefert_text_und_code(ev):
    e = _engine([("en", 0.95)], {"en": ("maybe this", -2.5), "th": ("", -9.0)})
    e.process(AUDIO, speak=False, uid="u2")
    dr = [kw for x, kw in ev if x == "dropped"][0]
    assert dr["code"] == "unsure" and dr["id"] == "u2" and dr["text"] == "maybe this" and dr["lang"] == "en"
    assert "heard" not in [x for x, _ in ev]


def test_drop_codes():
    assert d.drop_code("zu kurz") == "too_short"
    assert d.drop_code("nur Thai aktiv") == "locked" and d.drop_code("gesperrt") == "locked"
    assert d.drop_code("halluzination (wiederholung)") == "hallucination"
    assert d.drop_code("übersetzung fehlgeschlagen") == "translate_failed"
    assert d.drop_code("???") == "other"


def test_partner_stimme_gibt_keine_befehle(ev, monkeypatch):
    """Englisches "Translator, pause" mit Partner-Rolle (z. B. Video) wird nicht ausgeführt."""
    e = _engine([("en", 0.9)], {"en": ("Translator, pause.", -0.2), "th": ("ทรานสเลเตอร์", -0.3)}, role="other")
    e.lock = "auto"
    monkeypatch.setattr(d, "translate", lambda *a, **k: "Translator")
    e.process(AUDIO, speak=False, uid="u3")
    assert not e.paused and not any(x == "command" for x, _ in ev)


def test_korrektur_entfernt_alte_fassung_aus_kontext_und_repeat(ev, monkeypatch):
    e = _engine([("en", 0.9)], {"en": ("x", -0.2), "th": ("y", -0.2)})
    monkeypatch.setattr(d, "translate", lambda text, *a, **k: "OUT:" + text)
    e.deliver("a", "th", "ผิด", speak=True)
    assert e.last[2] == "a" and len(e.history) == 1
    e.retranslate("a", "ถูก", "th")
    assert [h[1] for h in e.history] == ["ถูก"]
    assert e.last[0] == "OUT:ถูก"
    # Korrektur eines älteren Satzes verdrängt den neuesten nicht aus "repeat"
    e.deliver("b", "en", "Hello", speak=True)
    newest = e.last
    e.deliver("c", "en", "Hi there", speak=True, replaces="a")
    assert e.last == newest


def test_reassign_heard_recent_begrenzt(ev, monkeypatch):
    e = _engine([("en", 0.9)], {"en": ("Where is it?", -0.2), "th": ("อยู่ที่ไหน", -0.3)})
    monkeypatch.setattr(d, "translate", lambda *a, **k: "Where is it?")
    monkeypatch.setattr(d, "RECENT_MAX", 3)
    for i in range(3):
        e.recent[f"r{i}"] = (np.zeros(d.SR, np.float32), None)
    e.reassign("r0", "other")
    assert "r0" not in e.recent and len(e.recent) <= 3
    assert any(x == "heard" and kw["lang"] == "th" for x, kw in ev)
    e.reassign("weg", "me")
    assert any(x == "error" and kw.get("code") == "reassign_expired" for x, kw in ev)


def test_text_lang_prueft_thai_anteil():
    assert d.text_lang("สวัสดีครับ", "en") == "th"
    assert d.text_lang("Hello there", "th") == "en"
    assert d.text_lang("Hello there", "en") == "en"
    assert d.text_lang("555", "th") == "th"


def test_say_phrase_ungueltig_meldet_fehler(ev):
    e = _engine([("en", 0.9)], {"en": ("x", 0), "th": ("y", 0)})
    e.say_phrase("hi", "de")
    assert ev[-1][0] == "error" and ev[-1][1]["code"] == "phrase_invalid"


def test_wake_fenster_startet_bei_speak_done(ev, monkeypatch):
    e = _engine([("en", 0.9)], {"en": ("x", 0), "th": ("y", 0)})
    e.command("")                           # bloßes "Translator"
    assert e._wake_wait
    monkeypatch.setitem(d._QSTATE, "speaker", types.SimpleNamespace(eng=e))
    e.awake_until = 0.0                     # Rückstand: Fenster wäre schon abgelaufen
    d._wake_after_reply()
    assert e.awake_until > d.time.monotonic() + d.WAKE_S - 1 and not e._wake_wait


def test_workqueue_zieht_jobs_vor():
    q = d.WorkQueue()
    a = (np.zeros(4), 0.1, 0.0, "vad")
    q.put(a)
    q.put(("pre", "u", 0, np.zeros(4)))
    q.put(("job", "J1"))
    q.put(None)
    q.put(("job", "J2"))
    assert q.qsize() == 5
    got = [q.get() for _ in range(5)]
    assert [g[1] if isinstance(g, tuple) and g[0] == "job" else g for g in got[:2]] == ["J1", "J2"]
    assert got[2] is a and got[3][0] == "pre" and got[4] is None


class _FakeVAD:
    N, CTX = 512, 64

    def __init__(self, probs):
        self.probs = iter(probs)

    def reset(self):
        pass

    def __call__(self, f):
        return next(self.probs, 0.0)


def _run_segmenter(monkeypatch, probs):
    monkeypatch.setattr(d, "StreamVAD", lambda: _FakeVAD(probs))
    monkeypatch.setattr(d.StreamVAD, "N", 512, raising=False)
    monkeypatch.setitem(d.FAST, "pre", False)
    N = 512
    frames = queue.Queue()
    for i, _ in enumerate(probs):
        frames.put((np.full(N, 0.1, dtype=np.float32), 1000.0 + i * N / d.SR))
    frames.put((np.zeros(0, dtype=np.float32), 0.0))
    utts = queue.Queue()
    d.segmenter(frames.get, utts)
    out = []
    while (x := utts.get_nowait()) is not None:
        if not isinstance(x[0], str):
            out.append(x)
    return out


def test_segmenter_zu_kurz_hat_id(ev, monkeypatch):
    # 3 Frames Sprache (~0,1 s), dann Stille -> "zu kurz" mit der id aus "hearing"
    out = _run_segmenter(monkeypatch, [0.9] * 3 + [0.0] * 40)
    assert not out
    hearing = [kw["id"] for x, kw in ev if x == "hearing"]
    dropped = [kw for x, kw in ev if x == "dropped"]
    assert dropped and dropped[0]["id"] == hearing[0] and dropped[0]["code"] == "too_short"


def test_segmenter_schneidet_bei_stille_und_max(ev, monkeypatch):
    monkeypatch.setattr(d, "SILENCE_END", 0.7)
    n_max = int(d.MAX_UTT / (512 / d.SR)) + 5
    out = _run_segmenter(monkeypatch, [0.9] * 30 + [0.0] * 30 + [0.9] * n_max + [0.0] * 30)
    reasons = [x[3] for x in out]
    assert reasons[0] == "vad" and "max" in reasons
    ids = [x[6] for x in out]
    assert len(set(ids)) == len(ids)            # jede Äußerung eigene id


def test_normalize_hebt_nicht_rauschen_und_ignoriert_knacken():
    noise = np.random.default_rng(0).normal(0, 0.0005, d.SR).astype(np.float32)
    out, _ = d.normalize(noise)
    assert np.array_equal(out, noise)                  # fast nur Rauschen: nicht ×10
    quiet = np.full(d.SR, 0.01, dtype=np.float32)
    quiet[100] = 0.9                                    # Knacken
    out, pk = d.normalize(quiet)
    assert pk == pytest.approx(0.9) and np.median(np.abs(out)) > 0.04   # trotzdem angehoben
    assert np.max(np.abs(out)) <= 1.0


def test_split_long_teilt_an_leiser_stelle():
    loud = np.full(d.SR * 50, 0.2, dtype=np.float32)
    loud[d.SR * 25: d.SR * 25 + 2048] = 0.0
    parts = d.split_long(loud, max_s=30.0)
    assert len(parts) == 2 and sum(p.size for p in parts) == loud.size
    assert abs(parts[0].size / d.SR - 25.1) < 0.2
    assert d.split_long(np.zeros(1000, np.float32)) and len(d.split_long(np.zeros(1000, np.float32))) == 1


def test_resolve_mic_nach_name(ev, monkeypatch):
    monkeypatch.setattr(d, "list_mics", lambda: [{"index": "0", "name": "MacBook Pro Microphone"},
                                                 {"index": "2", "name": "AirPods"}])
    assert d.resolve_mic("3") == "3"
    assert d.resolve_mic("airpods") == "2"
    assert d.resolve_mic("default") == "default"
    assert d.resolve_mic("USB Mic") == "default"
    assert ev[-1][1]["code"] == "mic_not_found"

    def boom():
        raise FileNotFoundError("ffmpeg")
    monkeypatch.setattr(d, "list_mics", boom)
    assert d.resolve_mic("AirPods") == "AirPods"       # avfoundation versteht den Namen direkt


def test_mic_start_wachhund_beendet_haengendes_ffmpeg(ev, monkeypatch):
    """Erster Read blockiert (Berechtigungsdialog/hängendes Gerät): nach MIC_START_TIMEOUT error + mic off."""
    monkeypatch.setattr(d, "MIC_START_TIMEOUT", 0.3)
    monkeypatch.delenv("DOLMETSCHER_MIC_FILE", raising=False)
    real, procs = subprocess.Popen, []

    def popen(*a, **k):
        procs.append(real(["sleep", "30"], stdout=subprocess.PIPE, stderr=subprocess.PIPE))
        return procs[-1]
    monkeypatch.setattr(d.subprocess, "Popen", popen)
    eng = types.SimpleNamespace(stop_speaking=lambda: None)
    m = d.Mic(eng, "0", queue.Queue(), idle=True)
    try:
        t = d.time.monotonic()
        assert m.start() is False
        assert d.time.monotonic() - t < 5
        assert procs and all(p.poll() is not None for p in procs)    # der Wachhund hat ffmpeg beendet
    finally:
        for p in procs:                                             # kein Zombie, falls die Prüfung scheitert
            if p.poll() is None:
                p.kill()
                p.wait()
    err = [kw for x, kw in ev if x == "error"][-1]
    assert err["code"] == "mic_timeout" and ("mic", {"on": False}) in ev


def test_fehlgeschlagene_korrektur_behaelt_alte_fassung(ev, monkeypatch):
    """Schlägt die Übersetzung der Korrektur fehl, bleibt die alte Blase korrigierbar (Audio, Kontext)."""
    e = _engine([("en", 0.9)], {"en": ("Where is it?", -0.2), "th": ("อยู่ที่ไหน", -0.3)})
    monkeypatch.setattr(d, "translate", lambda *a, **k: "Where is it?")
    e.recent["u1"] = (np.zeros(d.SR, np.float32), None)
    e.deliver("u1", "en", "Where is it?", speak=False)
    seen = {}

    def boom(text, src, dst, history=(), **k):
        seen["history"] = history
        raise RuntimeError("offline")
    monkeypatch.setattr(d, "translate", boom)
    e.reassign("u1", "other")
    assert "u1" in e.recent and len(e.history) == 1
    assert seen["history"] == ()                     # alte Fassung nicht als Kontext
    assert any(x == "dropped" and kw["code"] == "translate_failed" for x, kw in ev)


def test_laengerer_satz_schliesst_wake_fenster_endgueltig(ev, monkeypatch):
    e = _engine([("en", 0.95)], {"en": ("Where is the train station please?", -0.2), "th": ("x", -2.0)})
    monkeypatch.setattr(d, "translate", lambda *a, **k: "สถานี")
    e.command("")
    e.process(AUDIO, speak=False, uid="u9")
    assert e.awake_until == 0.0 and not e._wake_wait
