"""Runde 25: ausgelagerte reine Module (numwords, thaiparticles) und Fehler in Zahlen/Uhrzeit/Thai."""
import json

import pytest

import dolmetscher as d
import numwords
import thaiparticles


@pytest.mark.parametrize("name", ["thai_number_words", "speak_numbers_th", "_th_chunk", "_SPEAK_NUM",
                                  "_NUM_KEEP_BEFORE", "_TH_DIG", "_TH_POS"])
def test_numwords_reexport_is_same_object(name):
    assert getattr(d, name) is getattr(numwords, name)


@pytest.mark.parametrize("name", ["thai_speaker_sex", "fit_thai_particles", "thai_stretch", "_TH_KA", "_TH_KRUB",
                                  "_TH_FEMALE", "_TH_MALE", "_TH_Q_END", "_TH_STRETCH"])
def test_thaiparticles_reexport_is_same_object(name):
    assert getattr(d, name) is getattr(thaiparticles, name)


def test_modules_are_pure_no_engine_import():
    for mod in (numwords, thaiparticles):
        assert "dolmetscher" not in mod.__dict__


@pytest.mark.parametrize("n,words", [(0, "ศูนย์"), (11, "สิบเอ็ด"), (21, "ยี่สิบเอ็ด"), (101, "หนึ่งร้อยเอ็ด"),
                                     (350, "สามร้อยห้าสิบ"), (1_000_000, "หนึ่งล้าน"),
                                     (1_000_001, "หนึ่งล้านเอ็ด")])
def test_thai_number_words_values(n, words):
    assert numwords.thai_number_words(n) == words


@pytest.mark.parametrize("bad", [True, False, -1, 10 ** 12, 3.5, "5", None])
def test_thai_number_words_rejects_non_int(bad):
    assert numwords.thai_number_words(bad) is None


@pytest.mark.parametrize("text", ["เวลา 10.30 น.", "นัด 9.05 โมง", "15.00 นาฬิกา", "12.45น", "ประชุม 8.30 น"])
def test_clock_time_with_dot_stays_digits(text):
    assert numwords.speak_numbers_th(text) == text


def test_decimal_before_word_starting_with_no_is_still_a_decimal():
    assert numwords.speak_numbers_th("3.14 น้ำ") == "สามจุดหนึ่งสี่ น้ำ"


def test_out_of_range_clock_is_decimal():
    assert numwords.speak_numbers_th("25.30 น.") == "ยี่สิบห้าจุดสามศูนย์ น."


@pytest.mark.parametrize("text", ["10 000 บาท", "3 500 คน", "ราคา 1 234 567"])
def test_space_grouped_thousands_not_split(text):
    assert numwords.speak_numbers_th(text) == text


def test_separate_numbers_with_words_between_still_spoken():
    assert numwords.speak_numbers_th("ซื้อ 3 ชิ้น 500 บาท") == "ซื้อ สาม ชิ้น ห้าร้อย บาท"


def test_speak_form_uses_fixed_numbers_when_switch_on(monkeypatch):
    monkeypatch.setitem(d.SPEAK_NUMBER_WORDS, "on", True)
    assert d.speak_form("นัด 10.30 น. ราคา 350 บาท", "th") == "นัด 10.30 นาฬิกา ราคา สามร้อยห้าสิบ บาท"


def test_llm_spend_file_with_infinity_is_ignored(tmp_path, monkeypatch):
    f = tmp_path / "spend.json"
    monkeypatch.setattr(d, "LLM_SPEND_FILE", str(f))
    monkeypatch.setattr(d, "_SPEND", {"month": None, "usd": 0.0, "warned": None})
    for bad in ("Infinity", "NaN", "-Infinity"):
        f.write_text('{"month": "%s", "usd": %s}' % (d._month(), bad))
        d._SPEND.update(month=None, usd=0.0)
        assert d.llm_month_usd() == 0.0
    f.write_text(json.dumps({"month": d._month(), "usd": 1.25}))
    d._SPEND.update(month=None, usd=0.0)
    assert d.llm_month_usd() == 1.25
