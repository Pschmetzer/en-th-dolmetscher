"""Welle 8: adaptives TTS_RACE (reine Funktion, keine Uhr nötig)."""
import dolmetscher as d


def test_adaptive_race_needs_samples_and_respects_off():
    assert d.adaptive_race(1.4, [0.3] * 7) == 1.4
    assert d.adaptive_race(0.0, [0.3] * 20) == 0.0


def test_adaptive_race_good_network_shorter():
    assert d.adaptive_race(1.4, [0.25] * 20) == 0.8          # Untergrenze


def test_adaptive_race_bad_network_longer_but_capped():
    assert d.adaptive_race(1.4, [1.0] * 20) == 1.8
    assert d.adaptive_race(1.4, [5.0] * 20) == 2.8           # höchstens 2x base


def test_adaptive_race_ignores_single_outlier():
    s = [0.4] * 19 + [9.0]
    assert d.adaptive_race(1.4, s) == 0.9                    # p90, nicht Maximum
