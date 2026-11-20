"""Runde 21 (py1) Welle 6."""
import pytest

import dolmetscher as d


@pytest.mark.parametrize("text", [
    "Grazie per aver guardato!", "Legendas pela comunidade Amara.org", "Untertitelung des ZDF für funk, 2017",
    "チャンネル登録お願いします", "구독과 좋아요 부탁드립니다", "请订阅我的频道", "اشتركوا في القناة",
    "Cảm ơn các bạn đã theo dõi", "Izlediğiniz için teşekkürler", "Jangan lupa subscribe",
])
def test_more_outro_hallucinations_are_junk(text):
    assert d.is_junk(text)


@pytest.mark.parametrize("text", [
    "Grazie, mi può aiutare", "Cảm ơn bạn", "Izlediğim film güzeldi", "Guarda, il treno",
])
def test_real_sentences_are_not_junk(text):
    assert not d.is_junk(text)


def test_warm_translate_preloads_thai_romanizer(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "_get_json", lambda *a, **k: None)
    monkeypatch.setattr(d, "thai_latin", lambda t: calls.append(t))
    monkeypatch.setattr(d, "PAIR", ["en", "th"])
    monkeypatch.setitem(d.LLM, "on", False)
    d.warm_translate()
    assert calls
    calls.clear()
    monkeypatch.setattr(d, "PAIR", ["de", "en"])
    d.warm_translate()
    assert not calls


def test_warm_translate_survives_romanizer_errors(monkeypatch):
    monkeypatch.setattr(d, "_get_json", lambda *a, **k: None)
    monkeypatch.setattr(d, "thai_latin", lambda t: (_ for _ in ()).throw(RuntimeError("x")))
    monkeypatch.setitem(d.LLM, "on", False)
    d.warm_translate()


@pytest.mark.parametrize("text,expected", [
    ("Café Müller", True), ("Hotel Zürich", True), ("Łódź", True), ("Guten Morgen", False),
    ("où est la gare", False), ("Hotel California", True),
])
def test_looks_like_name_accented_latin(text, expected):
    assert d._looks_like_name(text) is expected


@pytest.mark.parametrize("raw,expected", [
    ("Translation: Hello", "Hello"), ("**Translation:** Hallo", "Hallo"), ("Traducción: hola", "hola"),
    ("> Übersetzung : Guten Tag", "Guten Tag"), ("翻译: 你好", "你好"),
    ("Thai: สวัสดี", "สวัสดี"), ("Translation of the text is hard", "Translation of the text is hard"),
])
def test_llm_prefix_labels_stripped(raw, expected):
    assert d._strip_quotes(d._LLM_PREFIX.sub("", raw)) == expected
