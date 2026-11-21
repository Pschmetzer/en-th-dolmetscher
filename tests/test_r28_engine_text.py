"""Runde 28: Zahlen (Hälfte mit Größenwort, Jahre als Wortpaar), Vorlesen (ISO-Währung, Maßeinheiten), STT ohne Text."""
import types

import pytest

import dolmetscher as d


@pytest.fixture(autouse=True)
def _pair():
    old = list(d.PAIR)
    d.set_pair("en", "th")
    yield
    d.PAIR[:] = old
    d._numbers_cached.cache_clear()


@pytest.mark.parametrize("raw,want", [
    ("one and a half million", 1_500_000), ("two and a half thousand", 2500), ("a million and a half", 1_500_000),
    ("3 and a half thousand", 3500), ("a hundred and a half", 150), ("two and a half hundred", 250),
    ("half a million", 500_000), ("twenty and a half thousand", 20_500),
])
def test_half_with_scale(raw, want):
    assert d.en_words_to_digits(raw).split() == [str(want)]


def test_half_without_scale_and_unknown_word_unchanged():
    assert d.en_words_to_digits("three and a half hours") == "3 and a half hours"
    assert d.en_words_to_digits("foo and a half thousand") == "foo and a half thousand"


@pytest.mark.parametrize("raw,want", [
    ("nineteen ninety nine", "1999"), ("nineteen eighty four", "1984"), ("nineteen seventy-one", "1971"),
    ("twenty twenty-six", "2026"), ("twenty twenty", "2020"), ("twenty twenty five", "2025"),
])
def test_year_pairs(raw, want):
    assert d.en_words_to_digits(raw).split() == [want]


@pytest.mark.parametrize("raw", ["twenty thirty", "twenty fifteen", "twenty twenty degrees",
                                 "nineteen thirty o'clock", "twenty one", "twenty", "nineteen",
                                 "nineteen eighty", "nineteen seventy", "nineteen twelve"])
def test_year_pairs_leave_clock_like_and_plain_numbers(raw):
    out = d.en_words_to_digits(raw)
    assert not any(t in out.split() for t in ("2030", "2015", "2020", "1930", "1980", "1970", "1912"))


def test_number_check_no_false_alarm_for_new_forms():
    assert not d.numbers_differ("two and a half thousand baht", "สองพันห้าร้อยบาท")
    assert not d.numbers_differ("one and a half million", "หนึ่งล้านห้าแสน")
    assert not d.numbers_differ("born in nineteen ninety nine", "เกิดปี 1999")
    assert d.numbers_differ("two and a half thousand baht", "สองพันบาท")            # echte Abweichung bleibt


@pytest.mark.parametrize("raw,lang,want", [
    ("THB 1,000 please", "th", "1,000 บาท please"), ("1,000 THB", "en", "1,000 baht"), ("USD20", "th", "20 ดอลลาร์"),
    ("EUR 5.50.", "en", "5.50 euros."), ("GBP 3", "de", "3 Pfund"),
    ("THB1000x", "th", "THB1000x"), ("MYTHB 5", "en", "MYTHB 5"), ("5 THBS", "en", "5 THBS"),
])
def test_speak_iso_currency(raw, lang, want):
    assert d.speak_form(raw, lang) == want


@pytest.mark.parametrize("raw,want", [
    ("5 km away", "5 กิโลเมตร away"), ("80 km/h", "80 กิโลเมตรต่อชั่วโมง"), ("2kg", "2 กิโลกรัม"),
    ("30 cm", "30 เซนติเมตร"), ("7mm", "7 มิลลิเมตร"), ("250 ml", "250 มิลลิลิตร"),
    ("50 kmh", "50 kmh"), ("10 mls", "10 mls"), ("km 5", "km 5"), ("a5km", "a5km"),
])
def test_speak_units_th(raw, want):
    assert d.speak_form(raw, "th") == want


def test_units_only_for_thai_voice():
    assert d.speak_form("5 km, 2 kg", "en") == "5 km, 2 kg"


def _seg(text):
    return types.SimpleNamespace(text=text, avg_logprob=-0.2, start=0.0, end=1.0)


class _Model:
    def __init__(self, segs):
        self.segs = segs

    def transcribe(self, audio, **kw):
        return iter(self.segs), None


@pytest.mark.parametrize("lang", ["en", "th"])
def test_stt_segment_without_text(lang):
    import numpy as np
    e = d.Engine.__new__(d.Engine)
    e.m = e.m_th = _Model([_seg(None), _seg(" hi "), _seg("")])
    e.beam = 1
    text, lp, segs = e._stt(np.zeros(16000, dtype="float32"), lang)
    assert text == "hi" and len(segs) == 3 and lp < 0
