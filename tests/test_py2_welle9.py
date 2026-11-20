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


def test_ctrl_spec_is_single_source():
    assert d.CTRL_KEYS == frozenset(d.CTRL_SPEC)
    assert d.CTRL_LOG_KEYS == frozenset(k for k, v in d.CTRL_SPEC.items() if v)


def test_secret_and_text_controls_never_logged():
    for k in ("api_key", "glossary", "say", "speak_text", "retranslate", "mic", "output_device", "reset_learning"):
        assert k in d.CTRL_KEYS and k not in d.CTRL_LOG_KEYS, k
    assert set(d.TEXT_CTRL_KEYS) <= d.CTRL_KEYS


def test_language_controls_derived_from_langs():
    for k in d.LANGS:
        assert f"tr_{k}" in d.CTRL_LOG_KEYS and f"voice_{k}" in d.CTRL_LOG_KEYS


def test_every_known_control_is_handled_by_apply_control():
    import inspect
    src = inspect.getsource(d.apply_control)
    dyn = {f"tr_{k}" for k in d.LANGS} | {f"voice_{k}" for k in d.LANGS}
    missing = sorted(k for k in d.CTRL_KEYS - dyn if f'"{k}"' not in src)
    assert not missing, missing


def test_numeric_controls_are_logged_values():
    for k in d.CTRL_NUMERIC:
        if k != "llm_budget":
            assert k in d.CTRL_LOG_KEYS


def test_player_close_standby_kills_warm_process():
    ev = []

    class In:
        def close(self):
            ev.append("eof")

    class P:
        stdin = In()

        def kill(self):
            ev.append("kill")
    p = d.Player()
    p._standby = (["x"], P())
    p.close_standby()
    assert ev == ["eof", "kill"] and p._standby is None
    p.close_standby()                                        # ohne Standby: nichts
