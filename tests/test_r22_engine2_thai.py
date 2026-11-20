"""Runde 22 (Engine 2): Thai-Normalisierung (Cache-Schlüssel, Dehnungen), Abkürzungen, Zahlwörter, Satzgrenzen,
Endpartikel, Log-Redaktion, Datenbank-Index, Stoppwörter, Satzbuch-Partikel, hwprofile, Versionsquelle."""
import json
import re
import sqlite3
from pathlib import Path

import pytest

import correction_learning as cl
import dolmetscher as d
import history_store
import hwprofile
import satzbuch

ROOT = Path(__file__).resolve().parent.parent


# ----------------------------------------------------------------------------------- Cache-Schlüssel / Dehnung

def test_norm_thai_leerzeichen_egal():
    assert d._norm("สวัสดี ครับ") == d._norm("สวัสดีครับ")


def test_norm_thai_dehnung_egal():
    assert d._norm("ขอบคุณครับบบบ") == d._norm("ขอบคุณครับ")


def test_norm_englisch_behaelt_leerzeichen():
    assert d._norm("Hello  World.") == "hello world"
    assert d._norm("a b") != d._norm("ab")


def test_norm_gemischt_lateinisch_thai():
    assert d._norm("ไป Chiang Mai ครับ") == d._norm("ไป Chiang Mai ครับ ")


def test_norm_lru_cache_aktiv():
    d._norm("cache me")
    before = d._norm.cache_info().hits
    d._norm("cache me")
    assert d._norm.cache_info().hits == before + 1


def test_cache_key_thai_ohne_leerzeichen():
    a = d._cache_key("ขอบคุณ มาก ครับ", "th", "en", False, "krub")
    b = d._cache_key("ขอบคุณมากครับ", "th", "en", False, "krub")
    assert a == b


@pytest.mark.parametrize("src, want", [
    ("ค่าาาา", "ค่า"), ("ครับบบบ", "ครับ"), ("ขอบคุณมากกกก", "ขอบคุณมาก"), ("ฮ่าๆๆๆ", "ฮ่าๆ"),
    ("ครับ", "ครับ"), ("ครับบ", "ครับบ"),          # zwei gleiche bleiben
    ("สวัสดี", "สวัสดี"), ("", ""), ("hello", "hello"), ("555", "555"),
])
def test_thai_stretch(src, want):
    assert d.thai_stretch(src) == want


def test_thai_latin_ist_gecacht():
    assert hasattr(d.thai_latin, "cache_info")


# ----------------------------------------------------------------------------------- Abkürzungen

@pytest.mark.parametrize("src, word", [
    ("พ.ศ. 2568", "พุทธศักราช"), ("ค.ศ. 2025", "คริสต์ศักราช"), ("ธ.ค. นี้", "ธันวาคม"),
    ("ม.ค. นี้", "มกราคม"), ("ต.ค. นี้", "ตุลาคม"), ("น.ส. สมศรี", "นางสาว"), ("ดร. สมชาย", "ดอกเตอร์"),
    ("นพ. สมชาย", "นายแพทย์"), ("บจก. ตัวอย่าง", "บริษัท จำกัด"), ("วิ่ง 5 กม.", "กิโลเมตร"),
    ("หนัก 3 กก.", "กิโลกรัม"), ("รอ 2 ชม.", "ชั่วโมง"), ("ไป ธ. กรุงเทพ", "ธนาคาร"), ("กทม.", "กรุงเทพมหานคร"),
])
def test_abbrev_erweitert(src, word):
    assert word in d.speak_form(src, "th")


def test_abbrev_nicht_mitten_im_wort():
    assert d.speak_form("พ.ศ.", "th") != "พ.ศ."
    assert d.speak_form("ธรรมดา", "th") == "ธรรมดา"        # ธ nicht ohne Punkt


def test_abbrev_nur_thai():
    assert d.speak_form("Dr. Smith 5 km", "en") == "Dr. Smith 5 km"


# ----------------------------------------------------------------------------------- Zahlwörter

@pytest.mark.parametrize("n, words", [
    (0, "ศูนย์"), (1, "หนึ่ง"), (7, "เจ็ด"), (10, "สิบ"), (11, "สิบเอ็ด"), (20, "ยี่สิบ"), (21, "ยี่สิบเอ็ด"),
    (25, "ยี่สิบห้า"), (100, "หนึ่งร้อย"), (101, "หนึ่งร้อยเอ็ด"), (350, "สามร้อยห้าสิบ"),
    (1000, "หนึ่งพัน"), (2025, "สองพันยี่สิบห้า"), (10000, "หนึ่งหมื่น"), (100000, "หนึ่งแสน"),
    (1000000, "หนึ่งล้าน"), (1000001, "หนึ่งล้านเอ็ด"), (1500000, "หนึ่งล้านห้าแสน"),
])
def test_thai_number_words(n, words):
    assert d.thai_number_words(n) == words


def test_thai_number_words_grenzen():
    assert d.thai_number_words(-1) is None and d.thai_number_words(10 ** 12) is None
    assert d.thai_number_words("5") is None


@pytest.mark.parametrize("n", [5, 11, 21, 99, 350, 12345, 999999, 1234567])
def test_zahlwoerter_roundtrip(n):
    """thai_words_to_digits (Gegenrichtung der Engine) liest die erzeugten Wörter wieder als dieselbe Zahl."""
    back = d.thai_words_to_digits(d.thai_number_words(n))
    assert str(n) in back.replace(",", "")


@pytest.fixture
def _zahlwort(monkeypatch):
    monkeypatch.setitem(d.SPEAK_NUMBER_WORDS, "on", True)


def test_speak_form_standard_ziffern():
    assert d.speak_form("ราคา 350 บาท", "th") == "ราคา 350 บาท"       # bestehendes Verhalten (Neural-TTS liest Ziffern)


def test_speak_form_zahl_als_wort(_zahlwort):
    assert d.speak_form("ราคา 350 บาท", "th") == "ราคา สามร้อยห้าสิบ บาท"


def test_speak_form_dezimal(_zahlwort):
    assert "สามจุดห้า" in d.speak_form("อุณหภูมิ 3.5 องศา", "th")


def test_speak_form_tausendertrenner(_zahlwort):
    assert "หนึ่งพันห้าร้อย" in d.speak_form("จ่าย 1,500 บาท", "th")


def test_speak_form_zimmer_und_zeit_bleiben(_zahlwort):
    out = d.speak_form("ห้อง 305 เวลา 10:30", "th")
    assert "305" in out and "10:30" in out


def test_speak_form_fuehrende_null_bleibt(_zahlwort):
    assert "007" in d.speak_form("รหัส 007", "th")


def test_speak_form_lachen_555_bleibt_lachen(_zahlwort):
    assert "ฮ่าฮ่าฮ่า" in d.speak_form("555 ตลกมาก", "th")


def test_speak_form_schalter_aus(monkeypatch):
    monkeypatch.setitem(d.SPEAK_NUMBER_WORDS, "on", False)
    assert d.speak_form("ราคา 350 บาท", "th") == "ราคา 350 บาท"


def test_speak_form_andere_sprache_unberuehrt():
    assert d.speak_form("The price is 350 baht", "en") == "The price is 350 baht"


def test_speak_form_dehnung():
    assert d.speak_form("ขอบคุณครับบบบ", "th") == "ขอบคุณครับ"


# ----------------------------------------------------------------------------------- Satzgrenzen

def test_split_thai_fragezeichen_ohne_leerzeichen():
    parts = d.split_sentences("ขอบคุณมากครับ?ผมต้องการห้องพักหนึ่งห้องสำหรับสองคนคืนนี้ครับ", "th", 20)
    assert len(parts) == 2 and parts[0].endswith("?")


def test_split_thai_zeilenumbruch():
    parts = d.split_sentences("ขอบคุณมากครับที่มาวันนี้\nผมต้องการห้องพักหนึ่งห้องสำหรับสองคนคืนนี้", "th", 20)
    assert len(parts) == 2


def test_split_thai_kurz_bleibt_ein_stueck():
    assert d.split_sentences("ขอบคุณครับ", "th") == ["ขอบคุณครับ"]


def test_split_thai_leerzeichen_wie_vorher():
    parts = d.split_sentences("ขอบคุณมากครับที่มาวันนี้ ผมต้องการห้องพักหนึ่งห้องสำหรับสองคนคืนนี้", "th", 20)
    assert len(parts) == 2


# ----------------------------------------------------------------------------------- Endpartikel

def _p(out, polite="krub", q=False, prov="google", style="polite", form="auto"):
    return d.add_thai_particle(out, polite, q, prov, style, form)


def test_partikel_mann_ergaenzt():
    assert _p("ขอบคุณมาก") == "ขอบคุณมากครับ"


def test_partikel_frau_ergaenzt():
    assert _p("ขอบคุณมาก", "ka") == "ขอบคุณมากค่ะ"


def test_partikel_frau_frage_ka_mit_hohem_ton():
    assert _p("คุณมีโต๊ะไหม", "ka", True) == "คุณมีโต๊ะไหมคะ"


def test_partikel_frage_ohne_fragewort_bekommt_maihm():
    assert _p("คุณมีโต๊ะว่าง", "krub", True) == "คุณมีโต๊ะว่าง ไหมครับ"


def test_partikel_vor_satzzeichen():
    assert _p("ขอบคุณมาก.") == "ขอบคุณมากครับ."


def test_partikel_nicht_doppelt():
    for s in ("ขอบคุณครับ", "ขอบคุณค่ะ", "ไปไหนคะ", "ขอบคุณนะครับ", "ได้ครับ."):
        assert _p(s) == s


def test_partikel_claude_unberuehrt():
    assert _p("ขอบคุณมาก", prov="claude") == "ขอบคุณมาก"


def test_partikel_nur_bei_polite():
    assert _p("ขอบคุณมาก", style="casual") == "ขอบคุณมาก"
    assert _p("ขอบคุณมาก", style="casual", form="polite") == "ขอบคุณมากครับ"
    assert _p("ขอบคุณมาก", style="polite", form="informal") == "ขอบคุณมาก"


def test_partikel_ohne_geschlecht_unberuehrt():
    assert _p("ขอบคุณมาก", polite=None) == "ขอบคุณมาก"


def test_partikel_leer_und_nicht_thai():
    assert _p("") == "" and _p("Thank you") == "Thank you"


# ----------------------------------------------------------------------------------- Log-Redaktion (Whitelist)

TEXT_SCHLUESSEL = ["text", "alt_text", "alts", "out", "would_say", "cmd_retry", "command", "reply"]


@pytest.mark.parametrize("key", TEXT_SCHLUESSEL)
def test_redact_versteckt_textschluessel(key):
    out = d._redact({key: "Geheimer Satz"})
    assert "Geheimer" not in json.dumps(out, ensure_ascii=False)


def test_redact_verschachtelt_und_liste():
    out = d._redact({"segment": {"text": "Geheim", "n": 3}, "alts": ["a b", "c d"]})
    s = json.dumps(out, ensure_ascii=False)
    assert "Geheim" not in s and "a b" not in s and '"n": 3' in s


def test_redact_whitelist_felder_bleiben():
    ok = {"id": "u1", "lang": "th", "s": 0.4, "provider": "google", "cached": False}
    assert d._redact(dict(ok)) == ok


def test_log_schreibt_keinen_text(monkeypatch):
    zeilen = []

    class L:
        def info(self, m): zeilen.append(m)
    monkeypatch.setattr(d, "_logger", lambda: L())
    monkeypatch.setattr(d, "LOG_TEXT", False)
    d.log({"translate": "ok", "text": "Vertraulicher Satz", "out": "Secret", "id": "u7"})
    assert zeilen and "Vertraulicher" not in zeilen[0] and "Secret" not in zeilen[0] and "u7" in zeilen[0]


def test_log_scrub_nutzername(monkeypatch):
    zeilen = []

    class L:
        def info(self, m): zeilen.append(m)
    monkeypatch.setattr(d, "_logger", lambda: L())
    monkeypatch.setattr(d, "LOG_TEXT", False)
    d.log({"pfad": "/Users/maxmustermann/Library/x"})
    assert "maxmustermann" not in zeilen[0]


# ----------------------------------------------------------------------------------- history_store

def test_history_indexe_lang_role(tmp_path):
    st = history_store.Store(str(tmp_path / "h.db"))
    names = {r[1] for r in st.db.execute("PRAGMA index_list(utt)")}
    assert {"utt_lang", "utt_role", "utt_session_ts"} <= names
    st.close()


def test_history_dublette_nutzt_index(tmp_path):
    st = history_store.Store(str(tmp_path / "h.db"))
    plan = " ".join(str(r) for r in st.db.execute(
        "EXPLAIN QUERY PLAN SELECT 1 FROM utt WHERE ts BETWEEN ? AND ? AND session = ? AND text = ? LIMIT 1",
        (1.0, 2.0, "s", "t")))
    assert "USING" in plan and "INDEX" in plan
    st.close()


def test_import_json_dublette_im_toleranzfenster(tmp_path):
    st = history_store.Store(str(tmp_path / "h.db"))
    row = {"time": "2023-11-14T22:13:20.000Z", "session": "s1", "lang": "en", "text": "Hello", "translation": "Hallo"}
    r1 = st.import_json(json.dumps([row]))
    r2 = st.import_json(json.dumps([row]))
    n = st.db.execute("SELECT COUNT(*) FROM utt").fetchone()[0]
    assert n == 1 and r1 != r2
    st.close()


def test_import_json_andere_session_ist_keine_dublette(tmp_path):
    st = history_store.Store(str(tmp_path / "h.db"))
    row = {"time": "2023-11-14T22:13:20.000Z", "session": "s1", "lang": "en", "text": "Hello"}
    st.import_json(json.dumps([row]))
    st.import_json(json.dumps([{**row, "session": "s2"}]))
    assert st.db.execute("SELECT COUNT(*) FROM utt").fetchone()[0] == 2
    st.close()


def test_migration_bestehende_db_bekommt_role_index(tmp_path):
    p = tmp_path / "alt.db"
    c = sqlite3.connect(p)
    c.execute("CREATE TABLE utt (id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT, ts REAL NOT NULL, session TEXT NOT NULL,"
              " lang TEXT, text TEXT, translation TEXT, translit TEXT, conf REAL, provider TEXT)")
    c.commit()
    c.close()
    st = history_store.Store(str(p))
    assert "utt_role" in {r[1] for r in st.db.execute("PRAGMA index_list(utt)")}
    st.close()


# ----------------------------------------------------------------------------------- correction_learning

def test_stopwoerter_deutsch():
    assert cl.suggest_vocab("ich möchte Wasser", "ich möchte und nicht Wasser Hotel", "de") == ["Hotel"]


def test_stopwoerter_franzose():
    assert "pour" not in cl.suggest_vocab("je veux", "je veux pour avec Bangkok", "fr")


def test_stopwoerter_je_sprache_nicht_global():
    # „die“ ist deutsches Funktionswort, aber nicht auf Englisch
    assert "die" in cl.suggest_vocab("I will", "I will die", "en")
    assert "die" not in cl.suggest_vocab("ich will", "ich will die Wurst", "de")


def test_stopwoerter_thai():
    assert "ขอบคุณ" not in cl.suggest_vocab("ไป", "ไป ขอบคุณ", "th")


def test_stopwoerter_unbekannte_sprache_wie_vorher():
    assert cl._skip("the") and not cl._skip("Bangkok") and not cl._skip_lang("Bangkok", "xx")


# ----------------------------------------------------------------------------------- satzbuch

@pytest.mark.parametrize("th", ["ขอบคุณค่ะ", "ขอบคุณครับ", "ไปไหนคะ", "ขอบคุณนะคะ", "ดิฉันชื่อมาลี"])
def test_satzbuch_partikel_erkannt(th):
    f = satzbuch._format("p", "phrases[0]", "phrases", "Thank you", th)
    assert any("Höflichkeitspartikel" in x["message"] if isinstance(x, dict) else "Höflichkeitspartikel" in str(x)
               for x in f)


@pytest.mark.parametrize("th", ["คะแนนสอบ", "ผักคะน้า", "ขอบคุณมาก"])
def test_satzbuch_partikel_falsche_freunde(th):
    f = satzbuch._format("p", "phrases[0]", "phrases", "Score", th)
    assert not any("Höflichkeitspartikel" in str(x) for x in f)


def test_satzbuch_glossar_ohne_partikelwarnung():
    f = satzbuch._format("p", "glossary[0]", "glossary", "Thanks", "ขอบคุณค่ะ")
    assert not any("Höflichkeitspartikel" in str(x) for x in f)


# ----------------------------------------------------------------------------------- hwprofile

def _run(out):
    class R:
        returncode, stdout = 0, out
    return lambda *a, **k: R()


def test_thermal_gedrosselt():
    assert hwprofile.thermal_throttled(_run("Note: No thermal warning level has been recorded\nCPU_Speed_Limit = 70\n"))


def test_thermal_nicht_gedrosselt():
    assert not hwprofile.thermal_throttled(_run("CPU_Speed_Limit = 100\n"))


def test_thermal_fehler_ist_false():
    def boom(*a, **k):
        raise FileNotFoundError
    assert hwprofile.thermal_throttled(boom) is False
    assert hwprofile.thermal_throttled(_run("")) is False


def test_power_saving_bei_hitze():
    def run(cmd, **k):
        class R:
            returncode = 0
            stdout = {"batt": "AC Power", "therm": "CPU_Speed_Limit = 60"}.get(cmd[-1], "")
        return R()
    assert hwprofile.power_saving(run) is True


def test_engine_nutzt_power_saving():
    src = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
    assert "battery_fn = hwprofile.power_saving" in src and "hwprofile.power_saving()" in src


# ----------------------------------------------------------------------------------- Version

def test_engine_version_aus_pyproject():
    m = re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "pyproject.toml").read_text(encoding="utf-8"), re.M)
    assert d.ENGINE_VERSION == m.group(1)


def test_engine_version_rueckfall(monkeypatch):
    monkeypatch.setattr(d.os.path, "dirname", lambda p: "/nicht/vorhanden")
    assert d._engine_version("9.9") == "9.9"


def test_build_sh_liest_dieselbe_quelle():
    assert "pyproject.toml" in (ROOT / "build.sh").read_text(encoding="utf-8")
