"""Thai-Zahlwörter im Zahlenvergleich, Thai-Klauseltrennung fürs Vorlesen, Frage-Partikel aus dem Original."""
import pytest

import dolmetscher as d
from tests.test_engine_pipeline import _engine, ev  # noqa: F401  (Fixture)


@pytest.mark.parametrize("src, out", [
    ("ราคาสามร้อยห้าสิบบาท", "ราคา 350 บาท"),
    ("ยี่สิบห้าบาท", "25 บาท"),
    ("ร้อยยี่สิบเอ็ด", "121"),
    ("ห้องสามศูนย์ห้า", "ห้อง 305"),                      # Ziffernfolge (Zimmer)
    ("สองพันห้าร้อย", "2500"),
    ("หนึ่งล้านห้าแสน", "1500000"),
    ("หนึ่งพันล้าน", "1000000000"),
])
def test_thai_words_to_digits(src, out):
    assert " ".join(d.thai_words_to_digits(src).split()) == out


@pytest.mark.parametrize("src", [
    "เรียบร้อยแล้ว", "ฉันสามารถไปได้", "ห้ามสูบบุหรี่", "ไปห้าง", "นั่งเก้าอี้", "ลดร้อยละ", "แสนดี",
    "ความสัมพันธ์", "ศูนย์การค้า", "สองสามวัน",          # สองสาม = "ein paar", keine 23
])
def test_thai_falsche_freunde_bleiben(src):
    assert d.thai_words_to_digits(src) == src


@pytest.mark.parametrize("a, b, differ", [
    ("350 baht for room 12", "สามร้อยห้าสิบบาท ห้อง 12", False),   # meldete vorher fälschlich
    ("350 baht", "สามร้อยห้าสิบบาท", False),
    ("530 baht", "สามร้อยห้าสิบบาท", True),
    ("Room 305", "ห้องสามศูนย์ห้า", False),
    ("Room 306, please", "ห้องสามศูนย์ห้าครับ", True),
    ("at 2 PM, 20 people", "บ่ายสองโมง 20 คน", False),
    ("1 million baht", "หนึ่งล้านบาท", False),
    ("1.5 million", "15 ล้าน", True),
    ("1.5 million", "1.5 ล้าน", False),
    ("1,500,000 baht", "1.5 ล้านบาท", False),
    ("2 million", "หนึ่งล้านห้าแสน", True),
    ("10% off, 300 baht", "ลดร้อยละ 10 ราคา 300 บาท", False),
    ("Done, 300 baht", "เรียบร้อยแล้ว 300 บาท", False),
    # englische Zahlwörter werden nicht umgerechnet: dann zählen Thai-Zahlwörter auch nicht (kein Fehlalarm)
    ("two hundred people, room 305", "สองร้อยคน ห้อง 305", False),
])
def test_numbers_differ_thai_words(a, b, differ):
    assert d.numbers_differ(a, b) is differ
    assert d.numbers_differ(b, a) is differ


def test_split_thai_nach_fragezeichen():
    s = "ห้องน้ำที่ใกล้ที่สุดในห้างนี้อยู่ที่ไหนคะ? ฉันต้องการไปที่สถานีรถไฟใต้ดินที่ใกล้ที่สุดตอนนี้เลยค่ะ"
    parts = d.split_sentences(s, "th")
    assert parts[0] == "ห้องน้ำที่ใกล้ที่สุดในห้างนี้อยู่ที่ไหนคะ?"
    assert "".join(parts).replace(" ", "") == s.replace(" ", "")


@pytest.mark.parametrize("src, q, out", [
    ("คุณชอบกาแฟค่ะ", True, "คุณชอบกาแฟคะ"),
    ("ขอบคุณค่ะ คุณชอบกาแฟค่ะ", True, "ขอบคุณค่ะ คุณชอบกาแฟคะ"),      # nur das letzte Partikel
    ("คุณชอบกาแฟค่ะ", False, "คุณชอบกาแฟค่ะ"),
    ("คะแนนดีค่ะ.", True, "คะแนนดีคะ."),
])
def test_fix_thai_frage_aus_original(src, q, out):
    assert d.fix_thai(src, "ka", question=q) == out
    assert d.fix_thai(src, "krub", question=q) == d.fix_thai(src, "krub")   # Mann: ครับ in beiden Fällen


def test_deliver_frage_partikel(ev, monkeypatch):  # noqa: F811
    e = _engine([("en", 0.9)], {"en": ("x", -0.2), "th": ("x", -0.3)})
    e.polite = "ka"
    monkeypatch.setattr(d, "translate", lambda *a, **k: "คุณชอบกาแฟค่ะ")
    assert e.deliver("q1", "en", "Do you like coffee?", speak=False)[2] == "คุณชอบกาแฟคะ"
    assert e.deliver("q2", "en", "I like coffee.", speak=False)[2] == "คุณชอบกาแฟค่ะ"
