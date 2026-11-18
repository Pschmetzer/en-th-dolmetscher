"""Runde 8 (Cloud): Zahlen- und Thai-Logik der Engine – Zahlwörter, Ziffern, Uhrzeiten, Höflichkeitsformen,
Fragen. Reine Funktionen, kein Netz, kein Modell."""
import pytest

import dolmetscher as d


# ---- Englische Zahlwörter -----------------------------------------------------------------------------------

@pytest.mark.parametrize("src,want", [
    ("costs three hundred fifty baht", "costs 350 baht"),
    ("twenty one", "21"), ("twenty-one", "21"),
    ("one hundred and twenty three", "123"),
    ("one hundred twenty-three", "123"),
    ("one thousand two hundred", "1200"),
    ("three thousand five hundred baht", "3500 baht"),
    ("fifteen hundred", "1500"),
    ("a thousand", "1000"), ("a hundred", "100"),
    ("two million", "2000000"),
    ("zero", "0"),
])
def test_en_words_to_digits(src, want):
    assert d.en_words_to_digits(src).strip() == want


@pytest.mark.parametrize("src", ["thousand", "Someone", "someone", "nineteen eighty", "money", "bone", "stone"])
def test_en_words_to_digits_leaves_other_text(src):
    assert d.en_words_to_digits(src) == src


def test_en_words_to_digits_empty_and_digits_only():
    assert d.en_words_to_digits("") == ""
    assert d.en_words_to_digits("room 305") == "room 305"


# ---- Thai-Zahlwörter ---------------------------------------------------------------------------------------

@pytest.mark.parametrize("src,want", [
    ("ราคาสามร้อยห้าสิบบาท", "ราคา 350 บาท"),
    ("สิบ", "10"), ("ยี่สิบ", "20"), ("ยี่สิบเอ็ด", "21"), ("สิบเอ็ด", "11"),
    ("หนึ่งพันสองร้อย", "1200"), ("สองหมื่น", "20000"), ("หนึ่งแสน", "100000"), ("สองล้าน", "2000000"),
    ("ห้องสามศูนย์ห้า", "ห้อง 305"),
    ("ห้าสิบบาท", "50 บาท"),
])
def test_thai_words_to_digits(src, want):
    assert d.thai_words_to_digits(src).strip() == want


@pytest.mark.parametrize("src", ["เรียบร้อย", "สามารถ", "ร้อยละ 5", "สองสาม", "สองสามวัน", "ศูนย์", "สวัสดี", ""])
def test_thai_words_to_digits_false_friends_stay(src):
    assert d.thai_words_to_digits(src) == src


# ---- _numbers: Normalisierung ------------------------------------------------------------------------------

@pytest.mark.parametrize("src,want", [
    ("1.500", ["1500"]), ("1,500", ["1500"]), ("1.5", ["1.5"]), ("1,234,567", ["1234567"]),
    ("๑๒๓", ["123"]), ("๑,๒๐๐", ["1200"]), ("５００", ["500"]),
    ("09", ["9"]), ("9:00", ["9"]), ("3:30", ["3.30"]), ("15:45", ["15.45"]), ("2:30 PM", ["14.30"]),
    ("12.50", ["12.50"]), ("1.5 million", ["1500000"]), ("", []), ("keine Zahl", []),
])
def test_numbers_normalisation(src, want):
    assert d._numbers(src) == want


def test_numbers_are_sorted_and_thai_digits_equal_arabic():
    assert d._numbers("๒๐๐ und 100") == d._numbers("100 und 200") == ["100", "200"]


def test_thai_laugh_555_is_not_a_number_but_555_baht_is():
    assert d._numbers("555") == []
    assert d._numbers("ha 555 baht") == ["555"]


def test_buddhist_year_is_converted_to_gregorian():
    assert d._numbers("พ.ศ. 2569") == ["2026"]


# ---- numbers_differ ----------------------------------------------------------------------------------------

@pytest.mark.parametrize("a,b", [
    ("500 baht", "๕๐๐ บาท"), ("1,500 baht", "1.500 บาท"), ("350 baht", "สามร้อยห้าสิบบาท"),
    ("two hundred baht", "๒๐๐ บาท"), ("3:30 pm", "15:30"), ("it costs 3.5 baht", "ราคา 3.5 บาท"),
    ("20% off", "ลด 20 เปอร์เซ็นต์"), ("no numbers here", "ราคา 350"), ("", ""), ("350", ""),
])
def test_numbers_same(a, b):
    assert d.numbers_differ(a, b) is False


@pytest.mark.parametrize("a,b", [
    ("It costs 350 baht", "ราคา 530 บาท"), ("100 baht", "1000 บาท"), ("50 apples", "60 apples"),
    ("table for 2", "โต๊ะ 3 ที่"), ("room 305", "ห้อง 350"),
])
def test_numbers_differ(a, b):
    assert d.numbers_differ(a, b) is True


def test_single_digit_as_word_is_not_a_difference():
    assert d.numbers_differ("table for 2", "โต๊ะสองที่") is False


def test_numbers_detail_names_only_the_wrong_numbers():
    assert d._numbers_detail("350 and 700", "350 and 770") == {"src": ["700"], "out": ["770"]}


def test_numbers_detail_is_limited_to_eight_each():
    a = " ".join(str(1100 + i) for i in range(20))   # 4-stellig: keine Tausendergruppe
    b = " ".join(str(5100 + i) for i in range(20))
    det = d._numbers_detail(a, b)
    assert len(det["src"]) == 8 and len(det["out"]) == 8


def test_numbers_differ_is_symmetric_for_plain_numbers():
    for a, b in (("100 baht", "1000 บาท"), ("room 305", "ห้อง 350")):
        assert d.numbers_differ(a, b) == d.numbers_differ(b, a)


@pytest.mark.xfail(strict=True, reason="Telefonnummer 0812345678 gegen 081-234-5678 wird als Zahlenabweichung "
                                       "gemeldet (Bindestriche zerlegen die Nummer, führende Null fällt weg)")
def test_phone_number_with_dashes_is_not_a_number_mismatch():
    assert d.numbers_differ("call 0812345678", "โทร 081-234-5678") is False


@pytest.mark.parametrize("hm,want", [("20", (20, 0)), ("3.30", (3, 30)), ("24", (0, 0)), ("25", None),
                                     ("3.75", None), ("abc", None), ("", None), ("1.5.3", None)])
def test_time_hm(hm, want):
    assert d._time_hm(hm) == want


# ---- fix_thai -----------------------------------------------------------------------------------------------

@pytest.mark.parametrize("src,polite,want", [
    ("ครับ/ค่ะ", "krub", "ครับ"), ("ครับ/ค่ะ", "ka", "ค่ะ"), ("ค่ะ/ครับ", "krub", "ครับ"),
    ("ผม/ฉัน", "krub", "ผม"), ("ผม/ฉัน", "ka", "ฉัน"),
    ("คุณ/ท่าน", "krub", "คุณ"),
    ("ฉันชื่อแอน", "krub", "ผมชื่อแอน"), ("ผมชื่อแอน", "ka", "ฉันชื่อแอน"),
    ("ขอบคุณค่ะ", "krub", "ขอบคุณครับ"), ("ขอบคุณครับ", "ka", "ขอบคุณค่ะ"),
])
def test_fix_thai_gender(src, polite, want):
    assert d.fix_thai(src, polite) == want


@pytest.mark.parametrize("src,polite", [("คะแนน", "krub"), ("ตัดผม", "ka"), ("ผมยาว", "ka"), ("ฉันทามติ", "krub"),
                                       ("", "ka"), ("hello world", "krub")])
def test_fix_thai_leaves_innocent_words(src, polite):
    assert d.fix_thai(src, polite) == src


def test_fix_thai_is_idempotent():
    for s in ("ครับ/ค่ะ ฉันชื่อแอน", "ขอบคุณค่ะ ผมไปก่อน"):
        for p in ("krub", "ka"):
            once = d.fix_thai(s, p)
            assert d.fix_thai(once, p) == once


def test_thai_speaker_sex():
    assert d.thai_speaker_sex("สวัสดีครับ") == "male"
    assert d.thai_speaker_sex("สวัสดีค่ะ") == "female"
    assert d.thai_speaker_sex("hello") is None and d.thai_speaker_sex("") is None


# ---- is_question ----------------------------------------------------------------------------------------------

@pytest.mark.parametrize("text,lang,want", [
    ("Where is the toilet", "en", True), ("Is it far?", "en", True), ("How nice", "en", False),
    ("what a day", "en", False), ("Great!", "en", False), ("Do you speak English", "en", True),
    ("¿Dónde está el baño", "es", True), ("Wo ist das Bad", "de", True), ("Où est la gare", "fr", True),
    ("ฉันไปไหน", "th", False), ("อะไร？", "th", True), ("", "en", False), (None, "en", False),
])
def test_is_question(text, lang, want):
    assert d.is_question(text, lang) is want


# ---- Umschrift ohne pythainlp -----------------------------------------------------------------------------------

def test_thai_latin_without_thai_text_is_none():
    assert d.thai_latin("hello") is None and d.thai_latin("") is None and d.thai_latin(None) is None


def test_thai_latin_missing_pythainlp_is_remembered(monkeypatch):
    import sys
    monkeypatch.setitem(d._THAINLP, "missing", False)
    monkeypatch.setitem(sys.modules, "pythainlp.tokenize", None)
    monkeypatch.setitem(sys.modules, "pythainlp.transliterate", None)
    monkeypatch.setitem(sys.modules, "pythainlp", None)
    assert d.thai_latin("สวัสดี") is None
    assert d._THAINLP["missing"] is True
