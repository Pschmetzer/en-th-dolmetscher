"""Py3 Welle 3: Steuerzeilen (listen/mic-Reihenfolge, mehrere Aufgaben), Mikrofon-Sitzung, Vorab-Erkennung."""
import queue
import types

import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def _mic(on=False):
    calls = []
    m = types.SimpleNamespace(on=on, mic="0", stops=0, start=lambda: calls.append("start") or True,
                              stop=lambda: calls.append("stop"), switch=lambda mv: calls.append(("switch", mv)))
    return m, calls


def _eng():
    return types.SimpleNamespace(translate_dir={}, voices={}, rate=0, volume=1.0, mute=False, polite="krub",
                                 speaker=None, lock="auto", say_phrase=lambda *a: None)


def test_listen_true_then_stop_skips_waiting_start(ev, monkeypatch):
    m, calls = _mic()
    monkeypatch.setattr(d, "MIC", m)
    job = d.apply_control(_eng(), {"listen": True})
    m.stops += 1                                    # Stopp-Knopf kam, bevor der Arbeits-Thread den Start ausführt
    job()
    assert calls == []


def test_listen_true_runs_start_when_not_stopped(ev, monkeypatch):
    m, calls = _mic()
    monkeypatch.setattr(d, "MIC", m)
    d.apply_control(_eng(), {"listen": True})()
    assert calls == ["start"]


def test_mic_with_listen_switches_running_microphone(ev, monkeypatch):
    m, calls = _mic(on=True)
    monkeypatch.setattr(d, "MIC", m)
    d.apply_control(_eng(), {"mic": "USB", "listen": True})()
    assert calls[0] == ("switch", "USB") and m.mic == "0"


def test_mic_with_listen_while_off_sets_device_for_start(ev, monkeypatch):
    m, calls = _mic(on=False)
    monkeypatch.setattr(d, "MIC", m)
    d.apply_control(_eng(), {"mic": "USB", "listen": True})()
    assert m.mic == "USB" and calls == ["start"]


def test_say_and_retranslate_in_one_line_both_run(ev, monkeypatch):
    ran = []
    e = _eng()
    e.say_phrase = lambda t, lg: ran.append(("say", t))
    e.retranslate = lambda uid, t, lg: ran.append(("re", t))
    job = d.apply_control(e, {"say": {"text": "hello", "lang": "en"}, "retranslate": {"id": "u", "text": "x"}})
    job()
    assert ran == [("say", "hello"), ("re", "x")]


def test_start_stale_session_does_not_set_on(ev, monkeypatch):
    """stop() zwischen Erstblock und on=True: Mic.on bleibt False."""
    monkeypatch.delenv("DOLMETSCHER_MIC_FILE", raising=False)
    m = d.Mic(types.SimpleNamespace(stop_speaking=lambda: None), "0", queue.Queue(), idle=True)

    class FF:
        stdout = types.SimpleNamespace(read=lambda n: b"\0" * n)
        stderr = []

        def poll(self):
            return 0
    monkeypatch.setattr(d, "resolve_mic", lambda *a, **k: "0")
    monkeypatch.setattr(d, "capture_cmd", lambda **k: ["x"])

    def popen(*a, **k):
        m.sess += 1                                  # Stopp während des Starts
        return FF()
    monkeypatch.setattr(d.subprocess, "Popen", popen)
    assert m.start() is False and m.on is False
