"""Runde 14: Datumsformate, BE-Jahr, Thai-Zahlwörter, Ordnungszahlen, Wochentage/Monate im Zahlenvergleich."""
import pytest

import dolmetscher as d


@pytest.mark.parametrize("a,b", [
    ("Check in 25/12/2026", "เช็คอิน 25 ธ.ค. 2569"), ("Check in 25.12.2026", "เช็คอิน 25 ธันวาคม 69"),
    ("25 Dec 2026", "25 ธ.ค. 69"), ("Dec 25, 2026", "25 ธ.ค. 69"), ("12/25/2026", "25 ธ.ค. 69"),
    ("2026-12-25", "25 ธ.ค. 2569"), ("25/12/2569", "25 December 2026"), ("1 Sept 2026", "1 ก.ย. 2569"),
    ("Monday", "วันจันทร์"), ("Friday to Sunday", "วันศุกร์ถึงวันอาทิตย์"), ("March 3", "3 มีนาคม"),
    ("the twenty-fifth of December", "วันที่ 25 ธันวาคม"), ("third floor", "ชั้น 3"),
    ("room three oh five", "ห้อง 305"), ("room 305", "ห้อง ๓๐๕"), ("1,500 baht", "พันห้าบาท"),
    ("3,500,000", "สามล้านห้า"), ("15,000", "หมื่นห้า"), ("250,000", "สองแสนห้าหมื่น"),
    ("50%", "ห้าสิบเปอร์เซ็นต์"), ("3-5 days", "3–5 วัน"),
])
def test_equivalent(a, b):
    assert d.numbers_differ(a, b) is False


@pytest.mark.parametrize("a,b", [
    ("25 Dec 2026", "26 ธ.ค. 69"), ("25 Dec 2026", "25 ธ.ค. 2570"), ("25/12/2026", "25 ธ.ค. 2568"),
    ("12/25/2026", "26 ธ.ค. 69"), ("2026-12-25", "25 ธ.ค. 2570"),
    ("Monday", "วันอังคาร"), ("Friday", "วันเสาร์"), ("March 3", "3 เมษายน"), ("on 3 Mar", "ใน 3 เม.ย."),
    ("the twenty-fifth of December", "วันที่ 26 ธันวาคม"), ("the 3rd floor", "ชั้นที่ 4"),
    ("room three oh five", "ห้อง 350"), ("1,500 baht", "พันสองบาท"), ("3,500,000", "สามล้านสี่"),
    ("50%", "หกสิบเปอร์เซ็นต์"), ("3-5 days", "3-6 วัน"), ("room 305", "ห้อง 350"),
])
def test_real_differences(a, b):
    assert d.numbers_differ(a, b) is True


def test_no_false_alarms_on_plain_words():
    assert d.numbers_differ("May I sit here? It is 500 baht", "ขอนั่งได้ไหม 500 บาท") is False
    assert d.numbers_differ("First of all, 200 baht", "ก่อนอื่น 200 บาท") is False
    assert d.numbers_differ("Monday", "วันจันทร์และวันอังคาร") is False      # eine Seite nennt mehr: keine Abweichung
    assert d.numbers_differ("Call Jan 081-234-5678", "โทร 0812345678") is False


def test_numbers_normalizes_dates_and_ordinals():
    assert d._numbers("25/12/2569") == d._numbers("25 December 2026")
    assert d._numbers("the twenty-fifth") == ["25"]
    assert d._numbers("พันห้า") == ["1500"]
