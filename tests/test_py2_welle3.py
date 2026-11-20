"""Welle 3 (Reisende): langsam wiederholen, vorletzten Satz wiederholen, Preisanzeige, Lärm-Hinweis."""
import collections
import types

import numpy as np
import pytest

import dolmetscher as d


@pytest.mark.parametrize("cmd,key", [
    ("repeat slowly", "repeat_slow"), ("say that again slower", "repeat_slow"), ("say it slowly", "repeat_slow"),
    ("repeat the previous one", "repeat_prev"), ("say the one before again", "repeat_prev"),
    ("repeat", "repeat"), ("again", "repeat"), ("slower", "slower"), ("slow down", "slower")])
def test_parse_repeat_variants(cmd, key):
    assert d.parse_command(cmd) == key


def _engine(calls):
    e = d.Engine.__new__(d.Engine)
    e.m_det, e.spk, e.lock, e.paused, e.awake_until = None, None, "auto", False, 0.0
    e.translate_dir = {"en": True, "th": True}
    e.history = collections.deque(maxlen=8)
    e.texts, e.recent, e.mute = {}, collections.OrderedDict(), False
    e.last, e.prev = ("neu", "th", "u2"), ("alt", "th", "u1")
    e.rate, e.volume, e.polite, e.voices, e.earcons = 0, 1.0, "krub", {}, False
    e.speaker = types.SimpleNamespace(add=lambda *a, **k: calls.append((a, k)))
    return e


def test_command_repeat_slow_and_prev(monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    calls = []
    e = _engine(calls)
    assert e.command("repeat slowly") is None
    assert calls[-1] == (("neu", "th", "cmd"), {"pin": True, "slow": True})
    assert e.command("repeat the previous one") is None
    assert calls[-1] == (("alt", "th", "cmd"), {"pin": True, "slow": False})
    e.prev = None
    assert e.command("repeat the previous one") == "Nothing to repeat yet."


def test_speaker_boost_slow_flag(monkeypatch):
    monkeypatch.setitem(d.SLOW, "on", False)
    sp = d.Speaker.__new__(d.Speaker)
    sp.eng = types.SimpleNamespace(rate=0)
    assert sp.boost(0, slow=True) == d.SLOW_RATE
    assert sp.boost(0) == 0


def test_price_info():
    assert d.price_info("ราคา 150 บาท", "It costs 150 baht", per_baht=0.026) == [{"thb": 150.0, "value": 3.9}]
    assert d.price_info("฿1,500 and $5") == [{"thb": 1500.0}]
    assert d.price_info("no money here", per_baht=0.03) == []
    many = d.price_info("100 baht 200 baht 300 baht 400 baht", per_baht=1)
    assert len(many) == d.PRICE_MAX


def test_currency_arg():
    assert d._currency_arg({"code": "eur", "per_baht": 0.026}) == ("EUR", 0.026)
    assert d._currency_arg(None) == (None, None)
    for bad in ({"code": "EURO", "per_baht": 1}, {"code": "EUR", "per_baht": 0}, {"code": "EUR"}, "EUR", 5):
        with pytest.raises(ValueError):
            d._currency_arg(bad)


def test_currency_control_sets_and_rejects(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    monkeypatch.setattr(d, "CURRENCY", {"code": None, "per_baht": None})
    e = types.SimpleNamespace(translate_dir={}, voices={}, lock="auto", mute=False, stop_speaking=lambda: None)
    d.apply_control(e, {"currency": {"code": "USD", "per_baht": 0.028}})
    assert d.CURRENCY == {"code": "USD", "per_baht": 0.028}
    d.apply_control(e, {"currency": {"code": "X", "per_baht": 1}})
    assert ("control_invalid", {"key": "currency", "reason": "value"}) in ev
    d.apply_control(e, {"currency": None})
    assert d.CURRENCY == {"code": None, "per_baht": None}


def test_noise_tracker_loud_background_triggers_once():
    n = d.NoiseTracker()
    hits = [n.update(0.08, 0.05) for _ in range(d.NoiseTracker.FRAMES)]
    assert hits[-1] is True and not any(hits[:-1])
    assert n.update(0.08, 0.05) is False                      # nach dem Treffer neu sammeln


def test_noise_tracker_quiet_or_speech_does_not_trigger():
    n = d.NoiseTracker()
    assert not any(n.update(0.01, 0.05) for _ in range(400))
    n = d.NoiseTracker()
    for i in range(400):
        assert n.update(0.08, 0.9 if i % 100 == 99 else 0.05) is False   # Sprache setzt die Messung zurück


def test_segmenter_split_resets_peak_rms_source():
    # Der Rest nach einem MAX_UTT-Schnitt bekommt seinen eigenen Pegel (Quelltext-Prüfung, kein Mikrofon nötig)
    src = open(d.__file__, encoding="utf-8").read()
    assert "peak_rms = max((float(np.sqrt(np.mean(x ** 2))) for x in tail)" in src
    assert np.sqrt(np.mean(np.full(4, 0.1) ** 2)) == pytest.approx(0.1)
