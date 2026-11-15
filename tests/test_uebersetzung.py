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
