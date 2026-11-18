"""Mehrsprachigkeit: Sprachtabelle, Sprachpaar (Protokoll `langs`, --langs), Rückwärtskompatibilität (ohne Paar
= en/th wie bisher), Thai-Logik nur mit Thai im Paar, Schrift-Plausibilität für mehrere Paare."""
import collections
import types

import numpy as np
import pytest

import dolmetscher as d

CODES = {"en", "th", "de", "es", "fr", "it", "pt", "nl", "ru", "zh", "ja", "ko", "vi", "id", "ar", "hi", "tr", "pl",
         "uk"}


@pytest.fixture(autouse=True)
def _pair_reset():
    d.set_pair(*d.DEFAULT_PAIR)
    yield
    d.set_pair(*d.DEFAULT_PAIR)


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    monkeypatch.setitem(d.LLM, "on", False)
    return events


def _eng(**kw):
    e = d.Engine.__new__(d.Engine)
    e.lock, e.paused, e.awake_until, e.mute, e.earcons = "auto", False, 0.0, False, False
    e.translate_dir = {k: True for k in d.PAIR}
    e.history, e.texts, e.last = collections.deque(maxlen=8), {}, None
    e.polite, e.rate, e.volume, e.voices = "krub", 0, 1.0, {k: None for k in d.PAIR}
    e.recent = collections.OrderedDict()
    e.spoken = []
    e.speaker = types.SimpleNamespace(add=lambda *a, **k: e.spoken.append(a))
    e.m, e.m_det, e.m_th, e.spk, e.two_person = None, None, None, None, False
    e.__dict__.update(kw)
    return e


# --- Sprachtabelle ---------------------------------------------------------------------------------------

def test_sprachtabelle_vollstaendig():
    assert set(d.LANGS) == CODES
    assert d.DEFAULT_PAIR == ("en", "th")
    tokenizer = pytest.importorskip("faster_whisper.tokenizer", reason="faster-whisper fehlt (requirements-dev.txt)")
    whisper = set(tokenizer._LANGUAGE_CODES)
    for code, v in d.LANGS.items():
        assert code in whisper, code
        assert v["name"] and v["de"] and v["say"], code
        assert v["script"] and all(s in d.SCRIPTS for s in v["script"]), code
        assert v["locale"].split("_")[0] == code, code
        assert isinstance(v["min_lp"], float) and -2.0 < v["min_lp"] < 0, code
        assert v["m"] != v["f"] and {v["m"], v["f"]} <= set(v["voices"]), code
        for voice in v["voices"]:                       # edge-tts-Namen: <code>-<Region>-<Name>Neural
            assert voice.startswith(code + "-") and voice.endswith("Neural"), voice
        assert d.MIN_LOGPROB[code] == v["min_lp"] and d.VOICE[code] == v["say"] and d.VOICES[code] == v["voices"]


def test_tabellenwerte_wie_bisher_fuer_en_th():
    assert d.MIN_LOGPROB["en"] == -1.0 and d.MIN_LOGPROB["th"] == -1.3
    assert d.VOICE["en"] == "Samantha" and d.VOICE["th"] == "Kanya"
    assert d.NEURAL == {"th": {"krub": "th-TH-NiwatNeural", "ka": "th-TH-PremwadeeNeural"},
                        "en": {"en": "en-US-AriaNeural"}}
    assert d.mt_code("zh") == "zh-CN" and d.mt_code("de") == "de"


# --- Paar und Rückwärtskompatibilität --------------------------------------------------------------------

def test_ohne_paar_altes_verhalten():
    assert d.PAIR == ["en", "th"] and d.TARGET == {"en": "th", "th": "en"}
    assert d.llm_system() is d.LLM_SYSTEM
    assert d.default_voice("en") == "en-US-AriaNeural"
    assert d.default_voice("th", "krub") == "th-TH-NiwatNeural"
    assert d.default_voice("th", "ka") == "th-TH-PremwadeeNeural"
    assert d.role_lang("me") == "en" and d.role_lang("other") == "th"
    assert d.thai_active()


@pytest.mark.parametrize("mine, partner, ok", [
    ("de", "th", True), ("es", "ru", True), ("DE", " ja ", True), ("de", "de", False), ("xx", "th", False),
    (None, "th", False), ("en", 5, False),
])
def test_parse_pair(mine, partner, ok):
    assert (d.parse_pair(mine, partner) is not None) == ok


def test_set_pair_aktualisiert_target_an_ort_und_stelle():
    t = d.TARGET
    assert d.set_pair("de", "ja")
    assert d.TARGET is t and t == {"de": "ja", "ja": "de"} and d.PAIR == ["de", "ja"]
    assert d.target_of("de") == "ja" and d.target_of("ja") == "de" and d.target_of("en") == "ja"
    assert not d.set_pair("de", "de") and d.PAIR == ["de", "ja"]


def test_protokoll_langs_setzt_paar_und_meldet(ev):
    e = _eng(lock="th")
    d.apply_control(e, {"langs": {"mine": "de", "partner": "ja"}, "tr_ja": False, "lang": "ja"})
    assert d.PAIR == ["de", "ja"]
    assert ("langs", {"mine": "de", "partner": "ja"}) in ev
    assert e.translate_dir == {"de": True, "ja": False} and e.lock == "ja"
    d.apply_control(e, {"lang": "th"})                  # nicht im Paar: ignoriert
    assert e.lock == "ja"


def test_protokoll_langs_sperre_ausserhalb_wird_auto(ev):
    e = _eng(lock="th")
    d.apply_control(e, {"langs": {"mine": "de", "partner": "es"}})
    assert e.lock == "auto"


@pytest.mark.parametrize("bad", [{"mine": "de", "partner": "de"}, {"mine": "xx", "partner": "th"}, "de,th", None,
                                 {"mine": "de"}])
def test_protokoll_langs_ungueltig(ev, bad):
    e = _eng()
    d.apply_control(e, {"langs": bad})
    assert d.PAIR == ["en", "th"]
    assert ev[-1][0] == "error" and ev[-1][1]["code"] == "langs_invalid"


def test_ohne_langs_feld_bleibt_paar(ev):
    e = _eng()
    d.apply_control(e, {"tr_th": False, "lang": "en"})
    assert d.PAIR == ["en", "th"] and e.translate_dir == {"en": True, "th": False} and e.lock == "en"
    assert not any(x[0] in ("langs", "error") for x in ev)


def test_stimme_je_sprache_und_mine_partner(ev):
    e = _eng()
    d.apply_control(e, {"langs": {"mine": "de", "partner": "ko"}, "voice_de": "de-DE-ChristophNeural",
                        "tr_partner": False})
    assert e.voices["de"] == "de-DE-ChristophNeural" and e.translate_dir["ko"] is False
    d.apply_control(e, {"voice_ko": "en-US-AriaNeural"})        # Stimme einer anderen Sprache
    assert e.voices["ko"] is None and ev[-1][1]["code"] == "voice_unknown"
    assert e.voice_for("ko") == "ko-KR-InJoonNeural"            # Partnersprache: Mann bei krub
    assert e.voice_for("de") == "de-DE-ChristophNeural"         # gewählt
    d.apply_control(e, {"voice_de": ""})
    assert e.voice_for("de") == "de-DE-TanjaNeural"             # Standard meiner Sprache: Frauenstimme


def test_command_ereignis_traegt_paar(ev):
    d.set_pair("de", "th")
    e = _eng()
    e.emit_state("", "")
    kw = ev[-1][1]
    assert kw["langs"] == {"mine": "de", "partner": "th"} and kw["tr"] == {"de": True, "th": True}
    assert kw["tr_en"] is True and kw["tr_th"] is True and kw["voice_en"] == ""


def test_llm_prompt_je_paar():
    assert "between German and Thai" in d.llm_system(("de", "th"))
    assert "ครับ" in d.llm_system(("th", "de")) and "restore them in German" in d.llm_system(("th", "de"))
    g = d.llm_system(("es", "ru"))
    assert "between Spanish and Russian" in g and "Thai" not in g and "{setting}" in g


# --- Thai-Logik nur mit Thai -----------------------------------------------------------------------------

def test_555_nur_mit_thai_als_lachen():
    assert d._numbers("room 555 and 555") == ["555"]                  # en/th: freistehendes 555 = Lachen
    d.set_pair("de", "es")
    assert d._numbers("room 555 and 555") == ["555", "555"]
    assert d.numbers_differ("Das kostet 555", "Cuesta 556")


def test_ziffern_anderer_schriften_im_zahlenvergleich():
    assert not d.numbers_differ("It costs 350", "يكلف ٣٥٠")
    assert not d.numbers_differ("It costs 350", "कीमत ३५० है")
    assert not d.numbers_differ("It costs 350", "３５０円です")


def test_deliver_ohne_thai_kein_fix_thai(ev, monkeypatch):
    d.set_pair("de", "ja")
    calls = []
    monkeypatch.setattr(d, "fix_thai", lambda *a, **k: calls.append(a) or a[0])
    monkeypatch.setattr(d, "translate", lambda text, src, dst, **k: f"[{src}->{dst}] {text}")
    monkeypatch.setattr(d, "thai_latin", lambda t: "LATIN")
    e = _eng()
    assert e.deliver("u1", "de", "Wo ist der Bahnhof?")[2] == "[de->ja] Wo ist der Bahnhof?"
    utt = next(kw for x, kw in ev if x == "utt")
    assert utt["to"] == "ja" and utt["text_latin"] is None and utt["out_latin"] is None
    assert not calls and e.spoken[-1][1] == "ja"


def test_deliver_thai_mit_anderer_sprache_nutzt_fix_thai(ev, monkeypatch):
    d.set_pair("de", "th")
    monkeypatch.setattr(d, "translate", lambda text, src, dst, **k: "ครับ/ค่ะ")
    monkeypatch.setattr(d, "thai_latin", lambda t: None)
    e = _eng(polite="ka")
    assert e.deliver("u1", "de", "Danke")[2] == "ค่ะ"


def test_asiatische_labels_nur_mit_thai_und_nicht_fuer_paarsprache():
    probs = [("ja", 0.6), ("th", 0.1), ("en", 0.05)]
    assert _eng()._guess_lang(probs) == "th"                       # en/th: Japanisch zählt zu Thai
    d.set_pair("th", "ja")
    assert _eng()._guess_lang(probs) == "ja"                       # ja im Paar: bleibt Japanisch
    d.set_pair("de", "ko")
    assert _eng()._guess_lang([("zh", 0.5), ("ko", 0.3), ("de", 0.1)]) == "ko"   # kein Thai: keine Faltung


def _proc_engine(probs, texts):
    class Det:
        def detect_language(self, audio=None, language_detection_segments=2):
            return probs[0][0], probs[0][1], probs
    e = _eng()
    e.m_det = Det()
    e._stt = lambda audio, lang, hotwords=None, model=None, quick=False: (
        *texts.get(lang, ("", -9.0)), [types.SimpleNamespace(compression_ratio=1.1)])
    return e


AUDIO = np.full(d.SR * 2, 0.05, dtype=np.float32)


def test_process_waehlt_nur_zwischen_den_zwei_sprachen(ev, monkeypatch):
    d.set_pair("de", "ja")
    monkeypatch.setattr(d, "translate", lambda text, src, dst, **k: f"{src}->{dst}")
    e = _proc_engine([("ja", 0.7), ("de", 0.2), ("en", 0.05)], {"ja": ("駅はどこですか", -0.2), "de": ("x", -2.0)})
    e.process(AUDIO, speak=False, uid="u1")
    utt = next(kw for x, kw in ev if x == "utt")
    assert utt["lang"] == "ja" and utt["to"] == "de" and utt["out"] == "ja->de"


def test_process_dritte_sprache_wird_verworfen(ev):
    d.set_pair("de", "ja")
    e = _proc_engine([("en", 0.9), ("de", 0.02), ("ja", 0.01)], {})
    e.process(AUDIO, speak=False, uid="u1")
    drop = next(kw for x, kw in ev if x == "dropped")
    assert drop["code"] == "other_language" and drop["reason"] == "weder Deutsch noch Japanisch"


def test_befehle_nur_mit_englisch_im_paar(ev, monkeypatch):
    monkeypatch.setattr(d, "translate", lambda text, src, dst, **k: "übersetzt")
    d.set_pair("de", "es")
    e = _proc_engine([("de", 0.9), ("es", 0.05)], {"de": ("Translator pause", -0.2)})
    e.process(AUDIO, speak=False, uid="u1")
    assert not e.paused and any(x == "utt" for x, _ in ev)
    d.set_pair("de", "en")
    ev.clear()
    e = _proc_engine([("en", 0.9), ("de", 0.05)], {"en": ("Translator, pause.", -0.2)})
    e.process(AUDIO, speak=False, uid="u2")
    assert e.paused


def test_sprachbefehle_mit_sprachnamen(ev):
    assert d.parse_command("German only") == "only:de"
    assert d.parse_command("Spanish off") == "es_off"
    assert d.parse_command("Thai only") == "thai" and d.parse_command("English off") == "en_off"
    d.set_pair("en", "de")
    e = _eng()
    e.command("German only")
    assert e.lock == "de"
    e.command("Thai only")                                      # nicht im Paar
    assert e.lock == "de" and "not one of" in ev[-1][1]["reply"]
    e.command("German off")
    assert e.translate_dir == {"en": True, "de": False}


def test_rolle_und_profilsprache():
    d.set_pair("th", "en")
    assert d.role_lang("me") == "en" and d.role_lang("other") == "th"      # ich = englisches Profil
    d.set_pair("de", "th")
    assert d.role_lang("me") == "de" and d.role_lang("other") == "th"
    assert d.profile_lang("en") == "de" and d.profile_lang("th") == "th"
    d.set_pair("de", "es")
    assert d.profile_lang("th") == "es"


# --- Schrift-Plausibilität -------------------------------------------------------------------------------

@pytest.mark.parametrize("pair, src, dst, text, out, bad", [
    (("en", "th"), "en", "th", "Where is the station?", "Where is the station?", True),
    (("en", "th"), "en", "th", "Where is the station?", "สถานีอยู่ที่ไหน", False),
    (("en", "th"), "th", "en", "สถานีอยู่ที่ไหน", "สถานีอยู่ที่ไหน", True),
    (("de", "ja"), "de", "ja", "Wo ist der Bahnhof?", "Wo ist der Bahnhof?", True),
    (("de", "ja"), "de", "ja", "Wo ist der Bahnhof?", "駅はどこですか", False),
    (("de", "ja"), "ja", "de", "駅はどこですか", "駅はどこですか", True),
    (("es", "ru"), "es", "ru", "¿Dónde está la estación?", "¿Dónde está la estación?", True),
    (("es", "ru"), "es", "ru", "¿Dónde está la estación?", "Где вокзал?", False),
    (("es", "ru"), "ru", "es", "Где вокзал?", "Где вокзал?", True),
    (("ko", "ar"), "ko", "ar", "역이 어디예요?", "역이 어디예요?", True),
    (("hi", "en"), "hi", "en", "स्टेशन कहाँ है", "Where is the station?", False),
    (("de", "es"), "de", "es", "Bahnhof", "Bahnhof", False),            # gleiche Schrift: keine Prüfung
    (("zh", "ja"), "zh", "ja", "车站在哪里", "车站在哪里", False),          # gemeinsame Han-Zeichen
])
def test_schrift_plausibilitaet(pair, src, dst, text, out, bad):
    d.set_pair(*pair)
    if bad:
        with pytest.raises(d._Implausible):
            d._check_llm(text, out, dst, src)
    else:
        assert d._check_llm(text, out, dst, src)


def test_check_llm_ohne_src_nimmt_andere_paarsprache():
    d.set_pair("de", "ru")
    with pytest.raises(d._Implausible):
        d._check_llm("Guten Morgen zusammen", "Guten Morgen zusammen", "ru")


def test_google_falsche_schrift(monkeypatch):
    monkeypatch.setattr(d, "_get_json", lambda u, t: [[["Где вокзал?", "x"]]])
    with pytest.raises(ValueError, match="Russisch statt Spanisch"):
        d.google_translate("Где вокзал?", "ru", "es")
    seen = []
    monkeypatch.setattr(d, "_get_json", lambda u, t: seen.append(u) or [[["你好", "x"]]])
    assert d.google_translate("Hallo", "de", "zh") == "你好" and "tl=zh-CN" in seen[0]


@pytest.mark.parametrize("pair, text, lang, want", [
    (("en", "th"), "สวัสดีครับ", "en", "th"),
    (("en", "th"), "Hello there", "th", "en"),
    (("de", "ja"), "こんにちは", "de", "ja"),
    (("de", "ja"), "Guten Tag", "ja", "de"),
    (("es", "ru"), "Привет", "es", "ru"),
    (("ru", "ja"), "Привет", "ja", "ru"),
    (("de", "es"), "Hola", "de", "de"),                                  # gleiche Schrift: Angabe gilt
])
def test_text_lang_je_paar(pair, text, lang, want):
    d.set_pair(*pair)
    assert d.text_lang(text, lang) == want


def test_satztrennung_cjk():
    s = "駅はどこですか。ここから遠いですか？電車で行きたいです。タクシーは高いですか。"
    parts = d.split_sentences(s, "ja", min_len=20)
    assert len(parts) >= 2 and "".join(p.replace(" ", "") for p in parts) == s
