"""Runde 21 (py1) Welle 8: Fallback-Kette über Fake-Transporte (kein Netz, keine Uhr)."""
import urllib.error

import pytest

import dolmetscher as d


@pytest.fixture
def net(monkeypatch):
    d._cache_clear()
    monkeypatch.setitem(d.LLM, "on", False)
    calls = []
    plan = {"google": None, "mymemory": None}

    def get_json(url, timeout):
        host = "google" if "googleapis" in url else "mymemory"
        calls.append(host)
        r = plan[host]
        if isinstance(r, Exception):
            raise r
        return r
    monkeypatch.setattr(d, "_get_json", get_json)
    monkeypatch.setattr(d, "_offline_mt", lambda *a, **k: None)
    yield plan, calls
    d._cache_clear()


GOOD_G = [[["Hallo", "Hello"]]]
GOOD_M = {"responseData": {"translatedText": "Hallo M", "match": 0.9}, "responseStatus": 200}
DOWN = urllib.error.URLError(OSError("down"))


def test_google_first(net):
    plan, calls = net
    plan["google"] = GOOD_G
    assert d._translate("Hello", "en", "de") == "Hallo" and calls == ["google"]


def test_google_down_mymemory_answers(net):
    plan, calls = net
    plan["google"], plan["mymemory"] = DOWN, GOOD_M
    meta = {}
    assert d._translate("Hello", "en", "de", meta=meta) == "Hallo M" and meta["provider"] == "mymemory"
    assert calls == ["google", "mymemory"]


def test_google_in_backoff_is_skipped_next_sentence(net):
    plan, calls = net
    plan["google"], plan["mymemory"] = urllib.error.HTTPError("u", 429, "x", {}, None), GOOD_M
    d._translate("Hello", "en", "de")
    calls.clear()
    d._translate("Good morning", "en", "de")
    assert calls == ["mymemory"]                   # Google pausiert: kein Versuch


def test_both_down_uses_offline_helper(net, monkeypatch):
    plan, calls = net
    plan["google"] = plan["mymemory"] = DOWN
    seen = {}

    def off(text, src, dst, e, meta):
        meta["provider"] = "offline"
        seen["e"] = e
        return "lokal"
    monkeypatch.setattr(d, "_offline_mt", off)
    meta = {}
    assert d._translate("Hello", "en", "de", meta=meta) == "lokal" and meta["provider"] == "offline"
    assert d._cache_get(d._cache_key("Hello", "en", "de", False, "krub")) is None   # Offline-Ergebnis nie cachen


def test_all_fail_raises_and_marks_offline(net):
    plan, calls = net
    plan["google"] = plan["mymemory"] = DOWN
    with pytest.raises(Exception):
        d._translate("Hello", "en", "de")
    calls.clear()
    with pytest.raises(RuntimeError, match="offline"):
        d._translate("Another one", "en", "de")
    assert calls == []                              # Offline-Schalter: sofort, ohne Netzversuch


def test_places_protected_and_localized(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [])
    t, slots = d._protect("Take me to Sukhumvit please", "th")
    assert slots == ["สุขุมวิท"] and "[1]" in t
    t, slots = d._protect("ไป สุขุมวิท ครับ", "en")
    assert slots == ["Sukhumvit"]
    t, slots = d._protect("Hotel in Hua Hin and Krabi", "de")
    assert slots == []                         # Latein -> Latein: nichts zu schützen


def test_places_roundtrip_via_provider(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [])
    monkeypatch.setattr(d, "_GLOSSARY_OWN", None)
    seen = []
    monkeypatch.setattr(d, "_get_json", lambda u, t: seen.append(u) or [[["ไป [1] ครับ", "x"]]])
    out = d.google_translate  # Anbieter direkt prüfen
    res = d._mt(out, "Go to Sukhumvit", "en", "th")
    assert res == "ไป สุขุมวิท ครับ" or "สุขุมวิท" in res
    assert "Sukhumvit" not in seen[0]


def test_own_glossary_beats_place_table(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("Siam", "ซีอาม")])
    monkeypatch.setattr(d, "_GLOSSARY_OWN", frozenset({("Siam", "ซีอาม")}))
    t, slots = d._protect("Siam Paragon", "th")
    assert slots == ["ซีอาม"]



# ---- Zweites Review: Regressionen ----

def test_review_fillers_keep_real_words():
    assert d.strip_fillers("Take him to the ER now", "en") == "Take him to the ER now"
    assert d.strip_fillers("To err is human", "en") == "To err is human"
    assert d.strip_fillers("Um, hello", "en") == "hello" and d.strip_fillers("erm, hello", "en") == "hello"


def test_review_kana_words():
    assert d.fit_thai_particles("ผัดคะน้าค่ะ", "krub") == "ผัดคะน้าครับ"
    assert d.thai_speaker_sex("ขอผัดคะน้าครับ") == "male"
    assert d.thai_speaker_sex("ขอผัดคะน้าหนึ่งจาน") is None


def test_review_fix_thai_unspaced():
    assert d.fix_thai("ได้ค่ะขอบคุณค่ะ", "krub") == "ได้ครับขอบคุณครับ"
    assert d.fix_thai("ได้ครับขอบคุณครับ", "ka") == "ได้ค่ะขอบคุณค่ะ"


def test_review_weak_words_not_commands_in_sentences():
    assert d.parse_command("pass me the salt") is None
    assert d.parse_command("start the car now") is None
    assert d.parse_command("stop") == "pause"


def test_review_url_not_corrupted_by_places(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [])
    t, slots = d._protect("Visit www.siam.com today", "th")
    assert slots == [] and t == "Visit www.siam.com today"


def test_review_no_effort_only_after_successful_retry(monkeypatch):
    import types

    class Err(Exception):
        status_code = 400

    class M:
        def create(self, **kw):
            raise Err("credit balance is too low")
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=M()))
    monkeypatch.setitem(d.LLM, "no_effort", False)
    with pytest.raises(Err):
        d.claude_translate("hello", "en", "th")
    assert d.LLM["no_effort"] is False


def test_review_thai_number_false_friends():
    assert not d.numbers_differ("We have been close for 10 years", "เราผูกพันกันมา 10 ปี")
    assert not d.numbers_differ("Roi Et is 500 km away", "ร้อยเอ็ดอยู่ห่าง 500 กิโลเมตร")


def test_review_valid_second_line_not_a_note():
    out = "Yes, we can go.\nAlternatively, we can take a taxi."
    assert d._check_llm("ได้ เราไปได้ หรือเรานั่งแท็กซี่ก็ได้", out, "en", "th") == out
    with pytest.raises(d._Implausible):
        d._check_llm("ได้", "Yes.\nNote: this is informal", "en", "th")


def test_review_abbrev_at_text_start():
    assert d.speak_form("ซ. 5 ถ. สุขุมวิท", "th").startswith("ซอย 5 ถนน")
