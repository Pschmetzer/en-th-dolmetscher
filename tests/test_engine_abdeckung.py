"""Bisher ungetestete Engine-Funktionen mit Risiko (aus der Abdeckungsmessung, IDEEN 110/195/196/301):
ffmpeg-Geräteliste parsen, macOS-Stimme wählen, Stimmabdruck automatisch nachführen, Mikrofon wieder
verbinden (mit gefälschter Uhr statt echter Wartezeit), vorläufiger Text. Ohne Hardware, Modelle und Netz."""
import types

import numpy as np
import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


# ---- list_mics über ffmpeg (DOLMETSCHER_FFMPEG) -------------------------------------------------------------

FFMPEG_LIST = """\
[AVFoundation indev @ 0x7f8] AVFoundation video devices:
[AVFoundation indev @ 0x7f8] [0] FaceTime HD Camera
[AVFoundation indev @ 0x7f8] [1] Capture screen 0
[AVFoundation indev @ 0x7f8] AVFoundation audio devices:
[AVFoundation indev @ 0x7f8] [0] MacBook Pro Microphone
[AVFoundation indev @ 0x7f8] [1] AirPods Pro [2. Gen]  \n\
[AVFoundation indev @ 0x7f8] [12] ZoomAudioDevice
[in#0 @ 0x600] Error opening input: Input/output error
"""


def test_list_mics_ffmpeg_nur_audio_geraete(monkeypatch):
    monkeypatch.setattr(d, "FFMPEG", "/x/ffmpeg")
    seen = {}

    def run(cmd, **kw):
        seen["cmd"] = cmd
        return types.SimpleNamespace(stdout="", stderr=FFMPEG_LIST, returncode=1)
    monkeypatch.setattr(d.subprocess, "run", run)
    assert d.list_mics() == [{"index": "0", "name": "MacBook Pro Microphone"},
                             {"index": "1", "name": "AirPods Pro [2. Gen]"},
                             {"index": "12", "name": "ZoomAudioDevice"}]
    assert seen["cmd"][0] == "/x/ffmpeg" and "avfoundation" in seen["cmd"]


def test_list_mics_ffmpeg_ohne_audio_abschnitt(monkeypatch):
    monkeypatch.setattr(d, "FFMPEG", "/x/ffmpeg")
    monkeypatch.setattr(d.subprocess, "run", lambda cmd, **kw: types.SimpleNamespace(
        stdout="", stderr="[AVFoundation indev @ 0x1] AVFoundation video devices:\n[x] [0] Kamera\n"))
    assert d.list_mics() == []


def test_list_mics_helper_nimmt_letzte_json_zeile(monkeypatch):
    monkeypatch.setattr(d, "FFMPEG", None)
    out = 'Warnung\n{"mics": [{"index": "0", "name": "alt"}]}\n{"mics": [{"index": "1", "name": "neu"}]}\n'
    monkeypatch.setattr(d.subprocess, "run", lambda cmd, **kw: types.SimpleNamespace(stdout=out, stderr=""))
    assert d.list_mics() == [{"index": "1", "name": "neu"}]


# ---- pick_voice ---------------------------------------------------------------------------------------------

SAY_LIST = """\
Kanya               th_TH    # สวัสดี
Narisa (Premium)    th_TH    # สวัสดี
Samantha            en_US    # Hello! My name is Samantha.
Ava (Enhanced)      en_US    # Hello! My name is Ava.
Anna                de_DE    # Hallo! Ich heiße Anna.
Petra (Erweitert)   de_DE    # Hallo! Ich heiße Petra.
Daniel              en_GB    # Hello! My name is Daniel.
Yuna                ko_KR    # 안녕하세요
"""


@pytest.mark.parametrize("lang, voices, want", [
    ("th", SAY_LIST, "Narisa (Premium)"),          # Premium der Locale vor der Tabellenstimme
    ("en", SAY_LIST, "Ava (Enhanced)"),            # Enhanced (nicht Daniel aus en_GB)
    ("de", SAY_LIST, "Petra (Erweitert)"),         # deutsche Systemsprache: „Erweitert“
    ("ko", SAY_LIST, "Yuna"),                      # nur Basisstimme: Tabellenstimme
    ("ru", SAY_LIST, "Milena"),                    # keine Stimme der Locale installiert: Tabellenstimme
    ("th", "", "Kanya"),                           # say-Liste leer/Fehler: Tabellenstimme
    ("xx", SAY_LIST, "Ava (Enhanced)"),            # unbekannte Sprache: wie Englisch
])
def test_pick_voice(monkeypatch, lang, voices, want):
    monkeypatch.setattr(d, "_say_voices", lambda: voices)
    assert d.pick_voice(lang) == want


@pytest.mark.xfail(strict=True, reason="pick_voice prüft die Tabellenstimme per Teilstring (`v not in out`): "
                   "'Milena2' gilt als installierte 'Milena' – Fehler, Produktcode hier nicht geändert")
def test_pick_voice_tabellenstimme_als_teilstring_gilt_nicht_als_installiert(monkeypatch):
    monkeypatch.setattr(d, "_say_voices", lambda: "Milena2            ru_RU    # Привет\n" + SAY_LIST)
    assert d.pick_voice("ru") == "Milena2"


def test_pick_voice_tabellenstimme_fehlt_nimmt_andere_der_locale(monkeypatch):
    monkeypatch.setattr(d, "_say_voices", lambda: "Yuri               ru_RU    # Привет\n" + SAY_LIST)
    assert d.pick_voice("ru") == "Yuri"


# ---- _learn_auto (Stimmabdruck nachführen) ----------------------------------------------------------------

class _Spk:
    def __init__(self, me=True, partner=True):
        self._me = {"name": "Ich"} if me else None
        self._partner = {"name": "Partnerin"} if partner else None
        self.learned = []

    def me(self):
        return self._me

    def partner(self):
        return self._partner

    def learn(self, name, emb, w):
        self.learned.append((name, emb, w))


def _learner(spk):
    return types.SimpleNamespace(spk=spk)


def _info(how="profil ich", sim_me=0.9, sim_her=0.9):
    return {"role_how": how, "sim_me": sim_me, "sim_her": sim_her}


def test_learn_auto_lernt_sicher_zugeordnete_lange_saetze():
    e = _learner(_Spk())
    d.Engine._learn_auto(e, "me", _info(), d.LEARN_MIN_S, "EMB")
    d.Engine._learn_auto(e, "partner", _info(how="vergleich"), d.LEARN_MIN_S + 1, "EMB2")
    assert e.spk.learned == [("Ich", "EMB", d.LEARN_W_AUTO), ("Partnerin", "EMB2", d.LEARN_W_AUTO)]


@pytest.mark.parametrize("role, info, dur", [
    ("me", _info(), d.LEARN_MIN_S - 0.01),                          # zu kurz
    ("me", _info(how="korrektur"), 5.0),                            # unsichere Zuordnungsart
    ("me", _info(how=None), 5.0),
    ("me", _info(sim_me=d.LEARN_MIN_SIM - 0.001), 5.0),             # knapp unter der Ähnlichkeitsschwelle
    ("me", _info(sim_me=None), 5.0),                                # ohne Embedding-Vergleich
    ("partner", _info(sim_me=0.99, sim_her=0.5), 5.0),              # Partnerrolle prüft sim_her, nicht sim_me
])
def test_learn_auto_lernt_nicht(role, info, dur):
    e = _learner(_Spk())
    d.Engine._learn_auto(e, role, info, dur, "EMB")
    assert e.spk.learned == []


def test_learn_auto_schwelle_inklusive_und_ohne_profil():
    e = _learner(_Spk(partner=False))
    d.Engine._learn_auto(e, "me", _info(sim_me=d.LEARN_MIN_SIM), 5.0, "EMB")
    d.Engine._learn_auto(e, "partner", _info(), 5.0, "EMB")            # kein Partnerprofil: nichts
    assert e.spk.learned == [("Ich", "EMB", d.LEARN_W_AUTO)]


def test_learn_auto_hoechstens_alle_learn_every_s_je_rolle():
    e = _learner(_Spk())
    d.Engine._learn_auto(e, "me", _info(), 5.0, "A")
    d.Engine._learn_auto(e, "me", _info(), 5.0, "B")                   # sofort danach: gesperrt
    d.Engine._learn_auto(e, "partner", _info(), 5.0, "C")              # andere Rolle: eigene Sperre
    assert [x[1] for x in e.spk.learned] == ["A", "C"]
    e._learn_t["me"] -= d.LEARN_EVERY_S                                # Frist abgelaufen (Uhr vorgestellt)
    d.Engine._learn_auto(e, "me", _info(), 5.0, "D")
    assert [x[1] for x in e.spk.learned] == ["A", "C", "D"]


def test_learn_auto_fehler_beim_schreiben_bricht_nicht_ab(monkeypatch):
    logs = []
    monkeypatch.setattr(d, "log", lambda x, *a, **k: logs.append(x))
    spk = _Spk()

    def boom(*a):
        raise OSError("Profildatei schreibgeschützt")
    spk.learn = boom
    d.Engine._learn_auto(_learner(spk), "me", _info(), 5.0, "EMB")
    assert logs and logs[-1]["learn"] == "fehler" and "schreibgeschützt" in logs[-1]["err"]


# ---- Mic._reconnect (gefälschte Uhr: STOP.wait schläft nicht) ----------------------------------------------

class _FakeStop:
    def __init__(self, stop_at=None):
        self.waits, self.stop_at = [], stop_at

    def wait(self, timeout=None):
        self.waits.append(timeout)
        return self.stop_at is not None and len(self.waits) >= self.stop_at

    def is_set(self):
        return False


def _mic(results):
    m = types.SimpleNamespace(stops=3, starts=0, failed=[])

    def start(_retry=False):
        assert _retry is True
        r = results[m.starts] if m.starts < len(results) else False
        m.starts += 1
        if isinstance(r, Exception):
            raise r
        return r
    m.start = start
    m._fail = lambda msg, retry, code=None: m.failed.append((msg, retry))
    return m


def test_reconnect_backoff_gibt_nicht_auf(monkeypatch, ev):
    # Nr. 192: nach den schnellen Versuchen weiter alle MIC_RETRY_SLOW s, bis Beenden/Erfolg – kein Aufgeben.
    stop = _FakeStop(stop_at=8)                                        # Engine endet während Versuch 8
    monkeypatch.setattr(d, "STOP", stop)
    monkeypatch.setattr(d, "MIC_RETRIES", 5)
    monkeypatch.setattr(d, "MIC_RETRY_SLOW", 10.0)
    m = _mic([False, RuntimeError("Gerät weg")])
    d.Mic._reconnect(m, 3)
    assert stop.waits == [1.0, 2.0, 4.0, 8.0, 10.0, 10.0, 10.0, 10.0]   # verdoppelt, dann dauerhaft 10 s
    assert m.starts == 7 and m.failed == []
    assert [kw["attempt"] for e, kw in ev if e == "mic"] == [1, 2, 3, 4, 5, 6, 7, 8]
    assert all(kw == {"on": False, "reconnecting": True, "attempt": kw["attempt"]} for e, kw in ev if e == "mic")


def test_reconnect_erfolg_beendet_schleife(monkeypatch, ev):
    stop = _FakeStop()
    monkeypatch.setattr(d, "STOP", stop)
    m = _mic([False, True])
    d.Mic._reconnect(m, 3)
    assert m.starts == 2 and stop.waits == [1.0, 2.0] and m.failed == []


def test_reconnect_abbruch_durch_beenden_oder_nutzerstopp(monkeypatch, ev):
    monkeypatch.setattr(d, "STOP", _FakeStop(stop_at=2))               # Engine wird während Versuch 2 beendet
    m = _mic([False])
    d.Mic._reconnect(m, 3)
    assert m.starts == 1 and m.failed == []
    monkeypatch.setattr(d, "STOP", _FakeStop())
    m = _mic([True])
    d.Mic._reconnect(m, 2)                                              # Nutzer hat inzwischen gestoppt
    assert m.starts == 0 and m.failed == []


# ---- partial (vorläufiger Text) -------------------------------------------------------------------------------

def _partial_engine(text="Hallo", detect=None):
    e = types.SimpleNamespace(calls=[])

    def det(audio, language_detection_segments=1):
        if detect:
            raise detect
        e.calls.append(("detect", audio.dtype, language_detection_segments))
        return "th", 0.9, [("th", 0.9)]
    e.m_det = types.SimpleNamespace(detect_language=det)
    e._guess_lang = lambda probs: probs[0][0]

    def stt(a, lang, model=None, quick=False):
        e.calls.append(("stt", lang, model is e.m_det, quick))
        return text, None
    e._stt = stt
    return e


def test_partial_meldet_text_mit_kleinem_modell(ev):
    e = _partial_engine("สวัสดี")
    d.Engine.partial(e, "u1", np.full(16000, 0.01, dtype=np.float32))
    assert e.calls == [("detect", np.float32, 1), ("stt", "th", True, True)]
    assert ev == [("partial", {"id": "u1", "text": "สวัสดี", "lang": "th"})]


def test_partial_leer_oder_fehler_meldet_nichts(ev, monkeypatch):
    logs = []
    monkeypatch.setattr(d, "log", lambda x, *a, **k: logs.append(x))
    d.Engine.partial(_partial_engine(""), "u1", np.zeros(8000, dtype=np.float32))
    e = _partial_engine(detect=RuntimeError("kaputt"))
    d.Engine.partial(e, "u2", np.zeros(8000, dtype=np.float32))
    assert ev == [] and e.calls == [] and logs[-1]["partial"] == "detect-fehler"
