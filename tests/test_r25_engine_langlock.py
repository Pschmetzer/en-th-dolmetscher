"""Runde 25: Charakterisierung der Sprachsperre und Spracherkennung vor einer möglichen Zusammenlegung von
detect_language und transcribe. Entscheidung: nicht zusammengelegt (siehe docs/PROTOKOLL.md, Runde 25) – die
Erkennung läuft mit dem kleinen Modell `m_det`, die Sperrlogik, Profil-Vorrang, Rollen und Gegenprobe brauchen die
Sprache VOR dem Dekodieren, und auch bei gesperrter Sprache verwirft die Wahrscheinlichkeit Geräusche. Diese Tests
halten das heutige Verhalten fest."""
import collections
import types

import numpy as np
import pytest

import dolmetscher as d

AUDIO = np.full(d.SR * 2, 0.05, dtype=np.float32)


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    monkeypatch.setitem(d.LLM, "on", False)
    monkeypatch.setitem(d.PARALLEL_ALT, "on", False)
    monkeypatch.setattr(d, "translate", lambda *a, **k: "ok")
    return events


def _engine(probs, texts, lock="auto", calls=None, detect_error=False):
    class Det:
        n = 0

        def detect_language(self, audio=None, language_detection_segments=2):
            Det.n += 1
            if detect_error:
                raise RuntimeError("boom")
            return probs[0][0], probs[0][1], probs
    e = d.Engine.__new__(d.Engine)
    e.m_det, e.m, e.m_th, e.lock, e.paused, e.awake_until = Det(), None, None, lock, False, 0.0
    e.spk, e.two_person = None, False
    e.translate_dir = {"en": True, "th": True}
    e.history, e.texts, e.last, e.mute = collections.deque(maxlen=8), {}, None, False
    e.polite, e.rate, e.volume, e.voices, e.earcons = "krub", 0, 1.0, {}, False
    e.recent = collections.OrderedDict()
    e.speaker = types.SimpleNamespace(add=lambda *a, **k: None)

    def stt(audio, lang, hotwords=None, model=None, quick=False):
        if calls is not None:
            calls.append((lang, quick))
        return (*texts[lang], [types.SimpleNamespace(compression_ratio=1.1)])
    e._stt = stt
    e._Det = Det
    return e


def _kinds(ev):
    return [k for k, _ in ev]


def test_lock_thai_decodes_thai_first_and_only_adds_english_wake_word_probe(ev):
    calls = []
    e = _engine([("en", 0.5), ("th", 0.4)], {"en": ("hello there", -0.2), "th": ("สวัสดีครับ", -0.3)},
                lock="th", calls=calls)
    e.process(AUDIO, speak=False, uid="u1")
    # erst die gesperrte Sprache; der zweite Aufruf ist nur die Weckwort-Prüfung, weil der Erkenner Englisch hört
    assert calls == [("th", False), ("en", False)]
    assert dict(ev)["heard"]["lang"] == "th" and "dropped" not in _kinds(ev)


def test_lock_thai_with_thai_detection_is_a_single_decode(ev):
    calls = []
    e = _engine([("th", 0.9), ("en", 0.05)], {"en": ("x", -0.2), "th": ("สวัสดีครับ", -0.3)}, lock="th", calls=calls)
    e.process(AUDIO, speak=False, uid="u1b")
    assert calls == [("th", False)]


def test_lock_runs_detector_once_per_sentence(ev):
    e = _engine([("th", 0.9)], {"en": ("x", -0.2), "th": ("สวัสดีครับ", -0.3)}, lock="th")
    e.process(AUDIO, speak=False, uid="u2")
    assert e._Det.n == 1                                  # Erkennung bleibt auch bei Sperre (Geräuschfilter)


def test_lock_still_drops_noise_that_is_neither_pair_language(ev):
    e = _engine([("fr", 0.95), ("en", 0.02), ("th", 0.01)], {"en": ("bonjour", -0.2), "th": ("", -9.0)}, lock="en")
    e.process(AUDIO, speak=False, uid="u3")
    dr = [kw for k, kw in ev if k == "dropped"]
    assert dr and "heard" not in _kinds(ev)


def test_auto_confident_single_decode_no_counter_check(ev):
    calls = []
    e = _engine([("en", 0.97), ("th", 0.01)], {"en": ("Where is the station?", -0.2), "th": ("x", -2.0)},
                calls=calls)
    e.process(AUDIO, speak=False, uid="u4")
    assert calls == [("en", False)]
    assert dict(ev)["heard"]["lang"] == "en"


def test_auto_uncertain_runs_quick_counter_check_in_other_language(ev):
    calls = []
    e = _engine([("en", 0.55), ("th", 0.4)], {"en": ("hmm", -0.9), "th": ("สถานีอยู่ที่ไหน", -0.2)}, calls=calls)
    e.process(AUDIO, speak=False, uid="u5")
    assert calls[0] == ("en", False) and calls[1] == ("th", True)
    assert dict(ev)["heard"]["lang"] == "th"              # die sicherere Gegenprobe gewinnt


def test_detector_failure_falls_back_to_lock_language_and_keeps_sentence(ev):
    calls = []
    e = _engine([("en", 0.9)], {"en": ("x", -0.2), "th": ("สวัสดีครับ", -0.3)}, lock="th", calls=calls,
                detect_error=True)
    e.process(AUDIO, speak=False, uid="u6")
    assert calls == [("th", False)]
    assert dict(ev)["heard"]["text"] == "สวัสดีครับ"


def test_detector_failure_in_auto_mode_tries_both_languages(ev):
    calls = []
    e = _engine([("en", 0.9)], {"en": ("good morning", -0.2), "th": ("", -9.0)}, calls=calls, detect_error=True)
    e.process(AUDIO, speak=False, uid="u7")
    assert {c[0] for c in calls} == {"en", "th"}          # 0,5/0,5: unsicher -> Gegenprobe in beiden Richtungen


def test_parallel_alt_does_not_change_the_result_of_the_counter_check(ev, monkeypatch):
    """Schalter parallel_alt (Standard aus) liefert dieselbe Sprache/denselben Text wie der sequenzielle Weg."""
    res = {}
    for on in (False, True):
        ev.clear()
        monkeypatch.setitem(d.PARALLEL_ALT, "on", on)
        e = _engine([("en", 0.55), ("th", 0.4)], {"en": ("hmm", -0.9), "th": ("สถานีอยู่ที่ไหน", -0.2)})
        e.process(AUDIO, speak=False, uid="u8")
        res[on] = (dict(ev)["heard"]["lang"], dict(ev)["heard"]["text"])
    assert res[False] == res[True]
