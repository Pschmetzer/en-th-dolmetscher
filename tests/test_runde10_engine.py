"""Runde 10: Maßeinheiten im Zahlenvergleich."""
import pytest

import dolmetscher as d


@pytest.mark.parametrize("a,b", [("It is 86 °F", "อากาศ 30 องศาเซลเซียส"), ("30°C today", "วันนี้ 86 °F"),
                                 ("10 miles away", "ห่างไป 16.1 กิโลเมตร"), ("It weighs 22 lb", "หนัก 10 กิโลกรัม"),
                                 ("5 km", "5 กิโลเมตร")])
def test_units_equivalent(a, b):
    assert d.numbers_differ(a, b) is False


@pytest.mark.parametrize("a,b", [("It is 86 °F", "อากาศ 35 องศาเซลเซียส"), ("10 miles", "10 กิโลเมตร")])
def test_units_real_differences(a, b):
    assert d.numbers_differ(a, b) is True


def test_canon_units_leaves_plain_text():
    assert d.canon_units("room 305") == "room 305"
