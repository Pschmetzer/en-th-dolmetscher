"""Welle 9: deklarative Steuertabelle (Schritt 1) und Konsistenz der Steuerfeld-Mengen."""
import pytest

import dolmetscher as d


def test_numeric_table_keys_are_known_controls():
    assert set(d.CTRL_NUMERIC) <= d.CTRL_KEYS
    for lo, hi in d.CTRL_NUMERIC.values():
        assert lo < hi


def test_logged_controls_are_known_controls():
    assert d.CTRL_LOG_KEYS <= d.CTRL_KEYS


@pytest.mark.parametrize("key", sorted(d.CTRL_NUMERIC))
def test_num_clamps_to_table_range(key, monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    lo, hi = d.CTRL_NUMERIC[key]
    assert d._num({key: 10 ** 9}, key) == hi
    assert d._num({key: -10 ** 9}, key) == lo
    assert d._num({}, key) is None and d._num({key: None}, key) is None


def test_num_invalid_and_bool_reported(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    assert d._num({"rate": True}, "rate") is None
    assert d._num({"rate": float("nan")}, "rate") is None
    assert len(ev) == 2 and ev[0][0] == "control_invalid"


def test_explicit_range_still_works():
    assert d._num({"x": 5}, "x", 0, 3) == 3
