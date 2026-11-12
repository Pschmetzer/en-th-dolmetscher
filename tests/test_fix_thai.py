import pytest

from dolmetscher import fix_thai


@pytest.mark.parametrize("src, krub, ka", [
    ("สวัสดีครับ/ค่ะ", "สวัสดีครับ", "สวัสดีค่ะ"),
    ("สวัสดีค่ะ / ครับ", "สวัสดีครับ", "สวัสดีค่ะ"),
    ("ไปไหนครับ/คะ", "ไปไหนครับ", "ไปไหนคะ"),
    ("ผม/ฉันหิว", "ผมหิว", "ฉันหิว"),
    ("ฉัน / ผมหิวครับ/ค่ะ", "ผมหิวครับ", "ฉันหิวค่ะ"),
    ("ขอบคุณ", "ขอบคุณ", "ขอบคุณ"),
])
def test_fix_thai(src, krub, ka):
    assert fix_thai(src, "krub") == krub
    assert fix_thai(src, "ka") == ka


from dolmetscher import strip_fillers, thai_latin


@pytest.mark.parametrize("src, want", [
    ("Um, I think so.", "I think so."),
    ("It's, you know, really good", "It's, really good"),
    ("I like it", "I like it"),
    ("uh", "uh"),
])
def test_strip_fillers_en(src, want):
    assert strip_fillers(src, "en") == want


def test_strip_fillers_th():
    assert strip_fillers("เอ่อ ไปไหนมา", "th") == "ไปไหนมา"


def test_strip_fillers_th_keeps_words():
    assert strip_fillers("ฉันชอบอ่านหนังสือ", "th") == "ฉันชอบอ่านหนังสือ"


def test_numbers_one_sided():
    assert not numbers_differ("ten minutes", "10 นาที")


def test_thai_latin_screenshot_sentences():
    pytest.importorskip("pythainlp")
    for s in ["ให้ฉันเปิดหน้าต่าง ฉันไม่สามารถมีกลิ่นที่นี่ มันแย่",
              "ฉันไม่รู้ บางครั้งมันก็ไม่ได้ผล แต่ฉันคิดว่ามันดีกว่าเมื่อก่อนแล้ว"]:
        out = thai_latin(s)
        assert out and out.isascii() and "็" not in out


def test_thai_latin():
    assert thai_latin("hello") is None
    pytest.importorskip("pythainlp")
    out = thai_latin("ขอบคุณมากครับ")
    assert out and out.isascii()


from dolmetscher import GLOSSARY, glossary_hits, load_glossary, numbers_differ


def test_numbers_differ():
    assert not numbers_differ("That costs 350 baht", "ราคา 350 บาท")
    assert numbers_differ("That costs 350 baht", "ราคา 530 บาท")
    assert not numbers_differ("hello", "สวัสดี")


def test_glossary(tmp_path, monkeypatch):
    import dolmetscher
    monkeypatch.setattr(dolmetscher, "GLOSSARY_FILE", str(tmp_path / "g.txt"))
    load_glossary("Sukhumvit\nNok => น้อก\n\n=> leer")
    assert glossary_hits("we live near sukhumvit") == [("Sukhumvit", None)]
    assert glossary_hits("Hi Nok") == [("Nok", "น้อก")]
    assert (tmp_path / "g.txt").exists()
    GLOSSARY.clear()


@pytest.mark.parametrize("src, want", [
    ("As you know, I am late", "As you know, I am late"),
    ("Would you like, a coffee", "Would you like, a coffee"),
    ("Sure, I mean, it's fine", "Sure, it's fine"),
    ("I said um.", "I said."),
])
def test_strip_fillers_keeps_meaning(src, want):
    assert strip_fillers(src, "en") == want


def test_numbers_normalized():
    assert not numbers_differ("๓๕๐ บาท", "350 baht")
    assert not numbers_differ("14:30", "14.30")
    assert not numbers_differ("ราคา 100 555", "price 100 haha")
