"""Runde 28 Thai-Sprachlogik: Partikel, Höflichkeitsstufe, Uhrzeit/Datum, Zahlwörter, Normalisierung, Satztrennung,
Namen, Satzbuch-Prüfung. Reine Funktionen, kein Netz, kein Modell."""
import random

import pytest

import correction_learning as cl
import numwords as nw
import satzbuch as sb
import textnorm as tn
import textsplit as ts
import thaiparticles as tp
import thaitime as tt


# ---- 1/2 Dehnung mit Tonzeichen, Schreibvarianten von ครับ
def test_stretch_tone_marks_and_particles():
    assert tp.thai_stretch("ค่่่ะ") == "ค่ะ"
    assert tp.thai_stretch("ครับบบบ") == "ครับ"
    assert tp.thai_stretch("ดีๆๆๆ") == "ดีๆ"
    assert tp.thai_stretch("ที่นี่") == "ที่นี่"                  # nichts zu dehnen
    assert tp.thai_stretch("") == "" and tp.thai_stretch(None) is None


@pytest.mark.parametrize("w", ["คร้าบ", "คร๊าบ", "ครัช"])
def test_male_spelling_variants(w):
    assert tp.thai_speaker_sex("ขอบคุณ" + w) == "male"
    assert tp.fit_thai_particles("ขอบคุณ" + w, "ka") == "ขอบคุณค่ะ"
    assert tp.fit_thai_particles("ขอบคุณค่ะ", "krub") == "ขอบคุณครับ"


def test_variants_with_both_genders_stay():
    assert tp.fit_thai_particles("เขาพูดว่า คร้าบ และ ค่ะ", "ka") == "เขาพูดว่า คร้าบ และ ค่ะ"


# ---- 3 Höflichkeitsstufe
@pytest.mark.parametrize("text,level", [
    ("ขอบคุณครับ", "polite"), ("ไปไหมคะ", "polite"), ("กระผมขอบคุณครับ", "formal"), ("ดิฉันขอโทษค่ะ", "formal"),
    ("มึงไปไหน", "rude"), ("ไปเว้ย", "rude"), ("กูไม่ไป", "rude"), ("ไปจ้ะ", "casual"), ("กินแล้วแหละ", "casual"),
    ("ครับ มึง", "rude"),                                         # die gröbste Stufe gewinnt
    ("กูเกิลครับ", "polite"), ("สวะ", None),                      # Google, สวะ sind keine Pronomen/Partikel
    ("คะแนนดี", None), ("อ่านหนังสือ", None), ("", None), (None, None)])
def test_politeness_level(text, level):
    assert tp.thai_politeness_level(text) == level


# ---- 4 คะ (Frage) / ค่ะ (Aussage)
@pytest.mark.parametrize("src,out", [
    ("ไปไหมค่ะ", "ไปไหมคะ"), ("ที่ไหนค่ะ", "ที่ไหนคะ"), ("ขอบคุณคะ", "ขอบคุณค่ะ"),
    ("ที่ไหนค่ะ ขอบคุณคะ", "ที่ไหนคะ ขอบคุณค่ะ"), ("ขอน้ำนะคะ", "ขอน้ำนะค่ะ"),
    ("คะแนนดีค่ะ", "คะแนนดีค่ะ"), ("ได้ไหมครับ", "ได้ไหมครับ"), ("ค่ะ", "ค่ะ"), ("", "")])
def test_normalize_ka(src, out):
    assert tp.normalize_ka(src) == out


# ---- 5/6 Uhrzeit: Mittag, นาฬิกา, „10.30 น.“
@pytest.mark.parametrize("src,out", [
    ("เจอกันเที่ยงครับ", "เจอกัน 12:00 ครับ"), ("เที่ยงครึ่ง", "12:30"), ("นัดเที่ยงตรง", "นัด 12:00"),
    ("ไม่เที่ยง", "ไม่เที่ยง"), ("เที่ยงธรรม", "เที่ยงธรรม"), ("เที่ยงคืน", "00:00"),
    ("14 นาฬิกา 30 นาที", "14:30"), ("9 นาฬิกา", "09:00"), ("25 นาฬิกา", "25 นาฬิกา"),
    ("10.30 น. ที่สนาม", "10:30 ที่สนาม"), ("25.30 น.", "25.30 น."), ("10.30 นาย", "10.30 นาย")])
def test_time_noon_and_clock(src, out):
    assert tt.th_times_for_mt(src) == out


# ---- 7/8 Datum, buddhistische Zeitrechnung
@pytest.mark.parametrize("src,out", [
    ("15 มกราคม 2569", "15 January 2026"), ("วันที่ ๓ ก.พ. ๒๕๗๐", "3 February 2027"),
    ("12 ธันวาคม", "12 December"), ("1 เมษายน ค.ศ. 2026", "1 April 2026"),
    ("31 กุมภาพันธ์ 2569", "31 กุมภาพันธ์ 2569"), ("29 กุมภาพันธ์ 2569", "29 กุมภาพันธ์ 2569"),
    ("29 กุมภาพันธ์ 2567", "29 February 2024"), ("31 เมษายน 2569", "31 เมษายน 2569"),
    ("5 มีนาคม 26", "5 March 26"), ("พ.ศ. 2569", "2026"), ("พ.ศ. 99", "พ.ศ. 99"),
    ("หนึ่งมกราคม", "หนึ่งมกราคม"), ("", "")])
def test_dates(src, out):
    assert tt.th_dates_for_mt(src) == out


def test_year_to_ce():
    assert tt.th_year_to_ce("2569") == 2026 and tt.th_year_to_ce("2026") == 2026
    assert tt.th_year_to_ce("๒๕๖๙") == 2026
    assert tt.th_year_to_ce("2026", "พ.ศ.") is None             # 1483 n. Chr. ist unplausibel
    assert tt.th_year_to_ce("0099") is None


# ---- 9 Zahlwörter -> Zahl
def test_words_to_number_round_trip():
    rng = random.Random(7)
    big = [rng.randrange(10 ** 12) for _ in range(2000)] + [10 ** 6, 10 ** 6 + 1, 10 ** 12 - 1]
    for v in list(range(0, 2500)) + big:
        assert nw.thai_words_to_number(nw.thai_number_words(v)) == v, v


@pytest.mark.parametrize("s,v", [("สามร้อยห้าสิบ", 350), ("ยี่สิบเอ็ด", 21), ("สองล้านห้าแสน", 2500000),
                                 ("สิบเอ็ดล้าน", 11000000), ("หนึ่งล้านเอ็ด", 1000001), ("สามร้อย", 300),
                                 ("สิบหนึ่ง", 11), ("ร้อยสาม", 103)])
def test_words_to_number_values(s, v):
    assert nw.thai_words_to_number(s) == v


@pytest.mark.parametrize("s", ["", None, "สองสอง", "เอ็ด", "ยี่", "ยี่ร้อย", "ล้าน", "abc", "สามบาท", "ศูนย์หนึ่ง",
                               "ห้าสิบร้อย", "สามร้อยสามร้อย"])
def test_words_to_number_invalid(s):
    assert nw.thai_words_to_number(s) is None


# ---- 10/11 Thai-Ziffern, Ziffernfolgen einzeln
def test_thai_digits_and_speak():
    assert nw.thai_digits_to_ascii("๑๒๓ abc ๙") == "123 abc 9" and nw.thai_digits_to_ascii(None) is None
    assert nw.speak_numbers_th("๓๐๐ บาท") == "สามร้อย บาท"
    assert nw.speak_numbers_th("ห้อง ๑๒๐๕") == "ห้อง 1205"      # Nummern bleiben Ziffern


def test_speak_digits():
    assert nw.speak_digits_th("081-234 5678") == "ศูนย์แปดหนึ่ง สองสามสี่ ห้าหกเจ็ดแปด"
    assert nw.speak_digits_th("๐๙") == "ศูนย์เก้า"
    assert nw.speak_digits_th("") == "" and nw.speak_digits_th("--") == ""


# ---- 12 Cache-Schlüssel
def test_norm_zero_width_and_thai_digits():
    assert tn._norm("สวัสดี​ครับ") == tn._norm("สวัสดีครับ")
    assert tn._norm("ห้อง ๓๐๕") == tn._norm("ห้อง 305")
    assert tn._norm("a﻿b") == "ab" and tn._norm("co­op") == "coop"


# ---- 13 Füllwörter
@pytest.mark.parametrize("src,out", [
    ("เอ่อ อืม ผมต้องการน้ำ", "ผมต้องการน้ำ"), ("เอ่อ", ""), ("อืม, ขอน้ำ", "ขอน้ำ"),
    ("อ่านหนังสือ", "อ่านหนังสือ"), ("เอ่อล้น", "เอ่อล้น"), ("ผมเอ่อ ไป", "ผมเอ่อ ไป"), ("", "")])
def test_strip_fillers(src, out):
    assert tn.strip_thai_fillers(src) == out


# ---- 14 Namensschlüssel
def test_name_key():
    assert len({tn.name_key(x) for x in ("Chiang Mai", "Chiangmai", "Chiang-Mai")}) == 1
    assert tn.name_key("Phuket") == tn.name_key("Puket")
    assert tn.name_key("Sukhumvit") == tn.name_key("Sukumvit")
    assert tn.name_key("Café") == "cafe"
    assert tn.name_key("") == "" and tn.name_key(None) == ""


# ---- 15 Thai-Sätze ohne Satzzeichen
def test_split_thai_sentences():
    assert ts.split_thai_sentences("สวัสดีครับ ผมชื่อจอห์น ไปสนามบินไหม ได้ครับ") == \
        ["สวัสดีครับ", "ผมชื่อจอห์น ไปสนามบินไหม", "ได้ครับ"]
    assert ts.split_thai_sentences("ได้ครับ 10 000 บาท คะแนนดี") == ["ได้ครับ", "10 000 บาท คะแนนดี"]
    assert ts.split_thai_sentences("ไปไหน? ผมไปตลาด!") == ["ไปไหน?", "ผมไปตลาด!"]
    assert ts.split_thai_sentences("สวัสดีครับผมชื่อจอห์น") == ["สวัสดีครับผมชื่อจอห์น"]
    assert ts.split_thai_sentences("") == [] and ts.split_thai_sentences(None) == []


# ---- 16 Thai-Kürzel trennen keinen Satz
def test_thai_abbreviations_rejoin():
    assert ts._rejoin_abbrev(["เจอกัน 10.30 น.", "ที่สนามบิน"]) == ["เจอกัน 10.30 น. ที่สนามบิน"]
    assert ts._rejoin_abbrev(["วันที่ 3 ก.พ.", "2569"]) == ["วันที่ 3 ก.พ. 2569"]
    assert ts._rejoin_abbrev(["ไปตลาด", "กินข้าว"]) == ["ไปตลาด", "กินข้าว"]


# ---- 17 Satzbuch: Thai-Prüfung
def _pack(*th):
    return {"phrases": [{"en": str(i), "th": t} for i, t in enumerate(th)], "glossary": []}


def test_satzbuch_check_thai():
    codes = lambda *th: [f["code"] for f in sb.check_thai("p", _pack(*th))]    # noqa: E731
    assert codes("ผมแพ้ถั่ว") == ["thai-gender"] and codes("ดิฉันแพ้ถั่ว") == ["thai-gender"]
    assert codes("ผมยาวมาก", "แพ้ถั่ว") == []                  # ผม = Haar
    assert codes("ไปไหนค่ะ") == ["thai-ka"] and codes("ขอบคุณคะ") == ["thai-ka"]
    assert codes("ไปไหนคะ", "ขอบคุณค่ะ", "เสื่อโยคะ", "คะแนนดี") == []
    assert codes("ดี​มาก") == ["thai-zerowidth"] and codes("ดีๆๆ") == ["thai-maiyamok"]
    assert codes("เล็ก ๆ") == []                                # Leerzeichen vor ๆ ist üblich


def test_satzbuch_presets_clean_with_thai_check():
    bad = [f for f in sb.check(thai=True) if f["code"].startswith("thai")]
    assert bad == []


def test_satzbuch_cli_thai_flag(capsys):
    assert sb.main(["check", "--thai"]) == 0


# ---- 18 Namen nach Anrede
def test_honorific_names():
    assert cl.thai_honorific_names("คุณสม ไป", "คุณสมชายครับ ไปไหม คุณไม่ไป นายวิชัยค่ะ") == ["สมชาย", "วิชัย"]
    assert cl.thai_honorific_names("คุณสมชาย", "คุณสมชายครับ") == []          # stand schon da
    assert cl.thai_honorific_names("", "คุณ") == [] and cl.thai_honorific_names("a", None) == []
    assert cl.thai_honorific_names("", "พี่นกนะ") == ["นก"]
    assert cl.thai_honorific_names("", "คุณสมชาย คุณสมชาย") == ["สมชาย"]


# ---- 19 Partikelvarianten sind keine Vokabeln
def test_particle_variants_not_suggested(monkeypatch):
    monkeypatch.setattr(cl, "_thai_tokens", lambda t: [x for x in t.split() if x])
    assert cl.suggest_vocab("ไป ตลาด", "ไป ตลาด คร้าบ เนอะ แหละ", "th") == []


# ---- 20 Namenszuordnung über den Namensschlüssel
def test_name_alignment_uses_name_key():
    assert cl.name_alignment("meet tong lor", "meet Thonglor") == [("tong lor", "Thonglor")]
    assert cl.name_alignment("go to pu get now", "go to Phuket now") == [("pu get", "Phuket")]
    assert cl.name_alignment("completely different", "go to Phuket now") == []
