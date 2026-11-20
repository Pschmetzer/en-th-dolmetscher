"""Welle 5 (Rückstand nach Wartezeit, Vorab-Laden, Mikrofon-Wachhund, Claude-Neuladen)."""
import types

import pytest

import dolmetscher as d


@pytest.mark.parametrize("kind,behind,chars,pin,slow,mode,want", [
    ("speech", 3, 0, False, False, "skip", True),          # wie bisher: drei Wartende
    ("speech", 2, 0, False, False, "skip", False),
    ("speech", 1, 600, False, False, "skip", True),        # neu: ein langer Rückstand reicht
    ("speech", 1, 599, False, False, "skip", False),
    ("speech", 0, 5000, False, False, "skip", False),      # nichts dahinter: nie überspringen
    ("speech", 3, 0, True, False, "skip", False),          # gepinnt (Befehlsantwort, Schnellsatz)
    ("speech", 3, 0, False, True, "skip", False),          # „Langsam und deutlich“
    ("speech", 3, 0, False, False, "fast", False),
    ("earcon", 3, 0, False, False, "skip", False)])
def test_skip_wanted(kind, behind, chars, pin, slow, mode, want):
    assert d.Speaker.skip_wanted(kind, behind, chars, pin, slow, mode, d.Speaker.SKIP_AT,
                                 d.Speaker.SKIP_CHARS) is want


def test_speaker_skips_by_waiting_text_without_streams(monkeypatch):
    """Zwei lange Ausgaben dahinter -> die ältere wird übersprungen, ohne dass sie je angefragt wurde."""
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    monkeypatch.setitem(d.CATCH_UP, "mode", "skip")
    monkeypatch.setitem(d.SLOW, "on", False)
    sp = d.Speaker.__new__(d.Speaker)
    sp.cond = d.threading.Condition()
    sp.items = d.collections.deque()
    sp.busy = False
    sp.eng = types.SimpleNamespace(tts="say", mute=True, rate=0)
    played = []
    sp._play = lambda it: played.append(it["id"])
    long_text = "x" * 700
    sp.items.extend([{"id": "a", "kind": "speech", "parts": [("kurz", None)], "pin": False},
                     {"id": "b", "kind": "speech", "parts": [(long_text, None)], "pin": False}])
    # Eine Schleifenrunde nachstellen: erstes Element holen und prüfen
    it = sp.items.popleft()
    behind = len(sp.items)
    waiting = sum(len(t) for other in sp.items for t, _ in other["parts"])
    assert sp.skip_wanted(it["kind"], behind, waiting, it.get("pin"), False, "skip", sp.SKIP_AT, sp.SKIP_CHARS)


def test_add_does_not_prefetch_under_heavy_backlog(monkeypatch):
    monkeypatch.setattr(d, "report_queue", lambda: None)
    monkeypatch.setitem(d.CATCH_UP, "mode", "skip")
    monkeypatch.setitem(d.SLOW, "on", False)
    prepared = []
    sp = d.Speaker.__new__(d.Speaker)
    sp.cond = d.threading.Condition()
    sp.items = d.collections.deque({"id": str(i), "parts": []} for i in range(2))
    sp.busy = True
    sp.eng = types.SimpleNamespace(rate=0)
    sp._prepare = lambda s, lang, boost: prepared.append(s) or (None, None)
    sp.add("Hello there my friend.", "en", "x")              # behind = 3 -> kein Vorab-Laden
    assert prepared == []
    sp.items.clear()
    sp.busy = False
    sp.add("Hello there my friend.", "en", "y")
    assert prepared


def test_mic_stalled():
    assert not d.mic_stalled(100.0, 102.0)
    assert d.mic_stalled(100.0, 106.0)
    assert d.mic_stalled(100.0, 102.0, limit=1.0)


def test_llm_reload_resets_state(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "llm_reset_backoff", lambda: calls.append("reset"))
    monkeypatch.setitem(d.LLM, "client", object())
    monkeypatch.setitem(d._LLM_AVAIL, "t", 5.0)
    d.llm_reload()
    assert d.LLM["client"] is None and d._LLM_AVAIL["t"] == 0.0 and calls == ["reset"]


def test_llm_control_uses_reload(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "llm_reload", lambda: calls.append(1))
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    e = types.SimpleNamespace(translate_dir={}, voices={}, lock="auto", mute=False, stop_speaking=lambda: None)
    d.apply_control(e, {"llm": True, "llm_retry": True})
    assert calls == [1, 1]


def test_model_load_timeout_defined_and_back_timeout_gone():
    assert d.MODEL_LOAD_TIMEOUT_S >= 600
    assert not hasattr(d, "BACK_TIMEOUT")


def test_power_check_switches_beam_and_reports(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    monkeypatch.setattr(d, "POWER", {"t": 0.0, "battery": None})
    e = types.SimpleNamespace(power_auto=True, beam=3)
    assert d.power_check(e, lambda: False, now=100.0) is True       # Start im Netzbetrieb: still
    assert e.beam == 3 and ev == []
    assert d.power_check(e, lambda: True, now=110.0) is False       # zu früh
    assert d.power_check(e, lambda: True, now=200.0) is True
    assert e.beam == 1 and ev[-1] == ("power", {"battery": True, "beam": 1})
    assert d.power_check(e, lambda: True, now=300.0) is False       # kein Wechsel
    assert d.power_check(e, lambda: False, now=400.0) is True
    assert e.beam == 3 and ev[-1] == ("power", {"battery": False, "beam": 3})


def test_power_check_only_with_auto_model_and_survives_errors(monkeypatch):
    monkeypatch.setattr(d, "POWER", {"t": 0.0, "battery": None})
    e = types.SimpleNamespace(beam=3)
    assert d.power_check(e, lambda: True, now=500.0) is False and e.beam == 3

    def boom():
        raise OSError("pmset")
    e.power_auto = True
    assert d.power_check(e, boom, now=600.0) is False and e.beam == 3


def test_power_check_keeps_user_beam_change_on_ac_return(monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setattr(d, "POWER", {"t": 0.0, "battery": None})
    e = types.SimpleNamespace(power_auto=True, beam=4)
    d.power_check(e, lambda: True, now=100.0)
    e.beam = 2                                                       # Nutzer stellt am Akku selbst um
    d.power_check(e, lambda: False, now=200.0)
    assert e.beam == 2


def test_local_voice_slot_acquire_is_cancellable():
    lv = d.LocalVoice.__new__(d.LocalVoice)
    held = [d.LocalVoice.SLOTS.acquire() for _ in range(2)]        # beide Plätze belegt
    try:
        assert lv._slot(lambda: True) is False
    finally:
        for _ in held:
            d.LocalVoice.SLOTS.release()
    assert lv._slot(lambda: False) is True
    d.LocalVoice.SLOTS.release()
