"""Übersetzung und Textverarbeitung: Lachen/555, Zahlen, Glossar, Cache, Plausibilität (ohne Netz)."""
import urllib.parse

import pytest

import dolmetscher as d


@pytest.fixture(autouse=True)
def _iso(monkeypatch):
    monkeypatch.setattr(d, "_CACHE", d.collections.OrderedDict())
    monkeypatch.setitem(d.LLM, "on", False)
    monkeypatch.setattr(d, "GLOSSARY", [])
    monkeypatch.setattr(d, "emit", lambda ev, **kw: None)


def _google_echo(seen, answer=None):
    """Fake-Google: merkt sich den gesendeten Text und antwortet mit `answer(text)`."""
    def gj(url, timeout=0):
        q = urllib.parse.unquote(url.split("q=")[1].split("&")[0])
        seen.append(q)
        return [[[answer(q) if answer else "ผลลัพธ์", "x"]]]
    return gj


# ---- 555 -----------------------------------------------------------------------------------------

@pytest.mark.parametrize("text", ["ราคา 555 บาท", "ห้อง 555", "เที่ยวบิน 555 ช้า", "เบอร์ 555 นะ", "1,555 บาท"])
def test_555_as_number_is_kept(monkeypatch, text):
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "Price 555 baht"))
    out = d.translate(text, "th", "en")
    assert seen == [text] and "haha" not in out


@pytest.mark.parametrize("text, sent", [("555", None), ("ดีมาก 555", "ดีมาก"), ("555 ไปไหนมา", "ไปไหนมา"),
                                        ("ตลกมาก 55555", "ตลกมาก"), ("ฮ่าๆ", None)])
def test_555_as_laugh(monkeypatch, text, sent):
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "Very good"))
    out = d.translate(text, "th", "en")
    assert out.endswith("haha") and seen == ([sent] if sent else [])


@pytest.mark.parametrize("a, b, differ", [
    ("ราคา 555 บาท", "Price 555 baht", False),
    ("ห้อง 555", "room 55", True),
    ("ราคา 100 555", "price 100 haha", False),
    ("2:30 PM", "14:30", False),
    ("at 2:30 PM", "บ่าย 2:30", False),
    ("9am", "09:00", False),
    ("3.5 km", "3,5 กม.", False),
    ("1.5", "15", True),
    ("350 baht", "530 บาท", True),
    ("two kids, 350 baht", "ลูก 2 คน 350 บาท", False),        # einstellige Zahl als Wort/Ziffer
    ("ten minutes", "10 นาที", False),
])
def test_numbers_differ_robust(a, b, differ):
    assert d.numbers_differ(a, b) is differ


# ---- Glossar -------------------------------------------------------------------------------------

def test_glossary_hits_word_boundaries(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Pat", None), ("Ao", "อ้อ"), ("สุขุมวิท", None)])
    assert d.glossary_hits("the path to Patrick") == []
    assert d.glossary_hits("also") == []
    assert d.glossary_hits("Hi pat!") == [("Pat", None)]
    assert d.glossary_hits("บ้านอยู่ที่สุขุมวิทนะ") == [("สุขุมวิท", None)]


def test_glossary_placeholders_with_google(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Nok", "น้อก"), ("Sukhumvit", None)])
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "โทรหา [1] ที่ [2] พรุ่งนี้"))
    out = d.translate("Call Nok in Sukhumvit tomorrow", "en", "th")
    assert seen == ["Call [1] in [2] tomorrow"]
    assert out == "โทรหา น้อก ที่ Sukhumvit พรุ่งนี้"


def test_glossary_reverse_direction(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Nok", "น้อก")])
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "[1] is coming"))
    assert d.translate("น้อก กำลังมา", "th", "en") == "Nok is coming"


def test_glossary_placeholder_lost_retranslates(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Nok", None)])
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "สวัสดีนก" if "[1]" in q else "สวัสดี Nok"))
    assert d.translate("Hello Nok", "en", "th") == "สวัสดี Nok"
    assert seen == ["Hello [1]", "Hello Nok"]


def test_glossary_only_names_skips_mt(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Nok", "น้อก")])
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: pytest.fail("kein Netz nötig"))
    assert d.translate("Nok!", "en", "th") == "น้อก!"


def test_glossary_written_atomic_and_private(tmp_path, monkeypatch):
    f = tmp_path / "sub" / "g.txt"
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(f))
    d.load_glossary("Nok => น้อก\n")
    assert f.read_text(encoding="utf-8") == "Nok => น้อก\n"
    assert (f.stat().st_mode & 0o777) == 0o600
    assert [p.name for p in f.parent.iterdir()] == ["g.txt"]          # keine Temp-Reste


def test_pronounce_word_boundaries_single_pass(monkeypatch):
    monkeypatch.setattr(d, "PRONOUNCE", [("Pat", "Pät"), ("Pät", "X"), ("New York", "Nju York")])
    assert d.apply_pronounce("Pat likes the pattern in new york") == "Pät likes the pattern in Nju York"


# ---- Cache ---------------------------------------------------------------------------------------

def test_cache_key_keeps_question_mark(monkeypatch):
    seen = []
    monkeypatch.setattr(d, "_get_json", _google_echo(seen, lambda q: "คุณมาไหม" if "?" in q else "คุณมา"))
    assert d.translate("You're coming.", "en", "th") == "คุณมา"
    assert d.translate("You're coming?", "en", "th") == "คุณมาไหม"
    meta = {}
    assert d.translate("you're coming ?", "en", "th", meta=meta) == "คุณมาไหม" and meta.get("cached")
    assert len(seen) == 2


def test_cache_cleared_by_glossary(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(tmp_path / "g.txt"))
    d._cache_put(("x", "en", "th", "mt", "krub"), ("y", "google"))
    d.load_glossary("Nok")
    assert d._cache_get(("x", "en", "th", "mt", "krub")) is None


# ---- fix_thai: Geschlecht konsequent ---------------------------------------------------------------

@pytest.mark.parametrize("src, krub, ka", [
    ("สวัสดีค่ะ", "สวัสดีครับ", "สวัสดีค่ะ"),
    ("ผมหิวครับ", "ผมหิวครับ", "ฉันหิวค่ะ"),
    ("ฉันชอบคะแนนนี้ค่ะ", "ผมชอบคะแนนนี้ครับ", "ฉันชอบคะแนนนี้ค่ะ"),     # คะแนน bleibt
    ("ตัดผมแล้วครับ", "ตัดผมแล้วครับ", "ตัดผมแล้วค่ะ"),                  # ผม = Haar bleibt
    ("ผมยาวมาก", "ผมยาวมาก", "ผมยาวมาก"),
    ("ผม ไปก่อนนะครับ", "ผม ไปก่อนนะครับ", "ฉัน ไปก่อนนะคะ"),
    ("คุณมาค่ะ?", "คุณมาครับ?", "คุณมาคะ?"),                             # ? aus dem Original
    ("ครับผม", "ครับผม", "ค่ะ"),
    ("ดิฉันชื่อน้อย", "ผมชื่อน้อย", "ดิฉันชื่อน้อย"),
])
def test_fix_thai_gender_consistent(src, krub, ka):
    assert d.fix_thai(src, "krub") == krub
    assert d.fix_thai(src, "ka") == ka


# ---- JUNK ----------------------------------------------------------------------------------------

@pytest.mark.parametrize("text", ["Thanks for watching!", "thank you for watching everyone",
                                  "ขอบคุณที่ติดตามรับชมนะครับ", "อย่าลืมกดไลค์ กดแชร์", "Please subscribe."])
def test_junk_variants(text):
    assert text in d.JUNK


@pytest.mark.parametrize("text", ["thanks for watching the kids", "hello", "", "Music festival", "ขอบคุณครับ"])
def test_junk_keeps_real_speech(text):
    assert text not in d.JUNK
