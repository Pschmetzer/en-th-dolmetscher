"""Runde 9: Telefonnummern, Brüche, Währungen, Tageszeiten im Zahlenvergleich."""
import pytest

import dolmetscher as d


@pytest.mark.parametrize("a,b", [("call 0812345678", "โทร 081-234-5678"), ("call 081 234 5678", "โทร 0812345678"),
                                 ("call +66 81 234 5678", "โทร 081-234-5678")])
def test_phone_formats_are_equal(a, b):
    assert d.numbers_differ(a, b) is False


def test_phone_real_difference_still_reported():
    assert d.numbers_differ("call 0812345678", "โทร 081-234-5679") is True


def test_date_and_price_not_treated_as_phone():
    assert d._numbers("05-06-2026") == sorted(d._numbers("05-06-2026"))
    assert d.numbers_differ("1 500 baht", "1600 บาท")


@pytest.mark.parametrize("s,want", [("1/2 kg", ["0.5"]), ("2 1/2 hours", ["2.5"]), ("half a kilo", ["0.5"]),
                                    ("ครึ่งกิโล", ["0.5"]), ("2 and a half", ["2.5"]),
                                    ("25/12/2026", ["12", "2026", "25"])])
def test_fractions(s, want):
    assert d._numbers(s) == want


def test_fraction_equivalence_and_difference():
    assert d.numbers_differ("1/2 kilo of rice", "ข้าวครึ่งกิโล") is False
    assert d.numbers_differ("1/2 kilo", "1/4 กิโล") is True


def test_currency_amounts():
    assert d.currency_amounts("฿500 and 5 dollars") == [("THB", "500"), ("USD", "5")]
    assert d.currency_amounts("ราคา 300 บาท") == [("THB", "300")]
    assert d.currency_amounts("no money 500") == []


def test_currency_mismatch():
    assert d.currency_mismatch("It costs 500 baht", "ราคา 500 ดอลลาร์")
    assert not d.currency_mismatch("It costs 500 baht", "ราคา 500 บาท")
    assert not d.currency_mismatch("It costs 500", "ราคา 500 บาท")
    assert d.numbers_differ("It costs 500 baht", "ราคา 500 ดอลลาร์") is True
    assert d.numbers_differ("฿1,500", "1500 บาท") is False


@pytest.mark.parametrize("a,b", [("3 pm", "15:00"), ("3 pm", "บ่ายสามโมง"), ("3 in the afternoon", "บ่ายสามโมง"),
                                 ("8 in the evening", "สองทุ่ม"), ("7 in the morning", "7:00"),
                                 ("12 at night", "เที่ยงคืน")])
def test_time_equivalence(a, b):
    assert d.numbers_differ(a, b) is False


def test_time_difference_reported():
    assert d.numbers_differ("meet at 3 pm", "นัด 16:00") is True
