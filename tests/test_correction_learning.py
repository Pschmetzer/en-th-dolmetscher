import types

import correction_learning as cl
import dolmetscher


def test_english_replacement():
    assert cl.suggest_vocab("send the invoice to the clinic", "send the invoice to the kliniq", "en") == ["kliniq"]


def test_numbers_units_skipped_proper_names_kept():
    # Nr. 209: Eigennamen sind die wertvollsten Vokabeln (früher fälschlich verworfen); "John" stand schon da
    out = cl.suggest_vocab("meet john at five", "meet John Smith at 5 kg tomorrow", "en")
    assert out == ["Smith", "tomorrow"]


def test_identical_and_empty():
    assert cl.suggest_vocab("hello there", "hello there", "en") == []
    assert cl.suggest_vocab("", "", "en") == []
    assert cl.suggest_vocab("hi", "", "en") == []


def test_sentence_start_capital_kept():
    assert cl.suggest_vocab("the ticket", "Booking ticket", "en") == ["Booking"]


def test_thai_segmentation_fallback(monkeypatch):
    # ohne pythainlp: Thai-Läufe als Wörter
    monkeypatch.setattr(cl, "_thai_tokens", lambda t: [x for x in t.split() if x])
    assert cl.suggest_vocab("ฉัน ไป ตลาด", "ฉัน ไป ตลาดน้ำ", "th") == ["ตลาดน้ำ"]


def test_thai_without_spaces_no_crash():
    out = cl.suggest_vocab("ฉันไปตลาด", "ฉันไปตลาดน้ำ", "th")
    assert isinstance(out, list)
    assert all(len(w) >= 2 for w in out)


def test_thai_number_skipped(monkeypatch):
    monkeypatch.setattr(cl, "_thai_tokens", lambda t: t.split())
    assert cl.suggest_vocab("ราคา สอง บาท", "ราคา 200 บาท", "th") == []


def test_retranslate_attaches_suggestions(monkeypatch):
    seen = {}
    fake = types.SimpleNamespace(texts={"u1": ("en", "see the clinic")},
                                 deliver=lambda *a, **k: seen.update(k))
    monkeypatch.setattr(dolmetscher, "new_id", lambda: "u2")
    dolmetscher.Engine.retranslate(fake, "u1", "see the kliniq", "en")
    assert seen["extra"] == {"suggest_vocab": ["kliniq"]}
    assert seen["replaces"] == "u1"


def test_retranslate_without_suggestion(monkeypatch):
    seen = {}
    fake = types.SimpleNamespace(texts={"u1": ("en", "hello")}, deliver=lambda *a, **k: seen.update(k))
    monkeypatch.setattr(dolmetscher, "new_id", lambda: "u2")
    dolmetscher.Engine.retranslate(fake, "u1", "hello", "en")
    assert seen["extra"] is None


def test_profile_cli_bad_name(monkeypatch):
    events = []
    monkeypatch.setattr(dolmetscher, "emit", lambda e, **k: events.append((e, k)))
    a = types.SimpleNamespace(profiles=False, delete_profile=None, vocab=["!!!", "a,b"], enroll=None)
    dolmetscher.profile_cli(a)
    assert events[0][0] == "error"
    a = types.SimpleNamespace(profiles=False, delete_profile=None, vocab=None, enroll="???", model="small")
    events.clear()
    dolmetscher.profile_cli(a)
    assert events[0][0] == "error"
