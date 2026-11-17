"""Runde 6 (Engine): Ideenliste Nr. 40, 42, 46, 51, 67, 69, 70, 74, 81, 171, 176, 177, 181, 197, 205, 206, 221,
243, 402."""
import json
import os
import pathlib
import subprocess
import sys
import threading
import types
import urllib.parse

import numpy as np
import pytest

import dolmetscher as d
import history_store as hs
import presets as P

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def _eng(**kw):
    base = dict(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False, paused=False,
                rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False, beam=1)
    base.update(kw)
    return types.SimpleNamespace(**base)


# ---- 40: "+" im Text übersteht den POST-Umbau (kein Fehler, Regressionstest) -----------------------------------

@pytest.mark.parametrize("text", ["1+1 = 2", "C++ & Co", "a%2Bb", "ราคา 100+ บาท", "x/y?z"])
def test_split_erhaelt_plus_und_sonderzeichen(text):
    url = f"https://translate.googleapis.com/translate_a/single?client=gtx&q={urllib.parse.quote(text)}"
    method, _, body = d.KeepAlive()._split(urllib.parse.urlsplit(url))
    assert method == "POST" and urllib.parse.parse_qs(body.decode())["q"] == [text]


# ---- 42: faster_whisper erst beim Laden ---------------------------------------------------------------------

def test_faster_whisper_nicht_beim_import():
    head = SRC[:SRC.index("SR = 16000")]
    assert "from faster_whisper import WhisperModel\n" not in head
    assert "WhisperModel = None" in head


def test_whisper_cls_nutzt_ersetztes_modell(monkeypatch):
    fake = object()
    monkeypatch.setattr(d, "WhisperModel", fake)
    assert d._whisper_cls() is fake


# ---- 46: Aufwärmen in der Sprache des Modells ---------------------------------------------------------------

class _FakeModel:
    def __init__(self):
        self.langs = []

    def detect_language(self, audio=None, **kw):
        return None, None, []

    def transcribe(self, audio, language=None, **kw):
        self.langs.append(language)
        return iter([]), None


def test_warm_thai_modell_auf_thai(monkeypatch):
    models = []

    def wm(model, **kw):
        models.append(_FakeModel())
        return models[-1]
    monkeypatch.setattr(d, "_wm", wm)
    d.load_model("x", "cpu", "th")
    d.load_model("y", "cpu")
    assert [m.langs for m in models] == [["th"], ["en"]]


def test_engine_waermt_thai_modell_mit_th():
    assert 'load_model(name, self.device, "th" if key == "th" else "en")' in SRC


# ---- 51: Geschlecht aus Thai-Partikeln ----------------------------------------------------------------------

@pytest.mark.parametrize("text, sex", [
    ("ไปไหนคะ", "female"), ("ขอบคุณค่ะ", "female"), ("ดิฉันชื่อแพร", "female"),
    ("ได้ครับ", "male"), ("กระผมขอโทษ", "male"),
    ("คะแนนดีมาก", None), ("ไปไหน", None), ("ต้องบังคับใช้กฎ", None), ("ห้องคับแคบค่ะ", "female"),
    ("เขาบอกว่าครับ ฉันตอบว่าค่ะ", None), ("", None),
])
def test_thai_speaker_sex(text, sex):
    assert d.thai_speaker_sex(text) == sex


def _claude_body(monkeypatch, text, src, dst):
    sent = {}

    class Msgs:
        def create(self, **kw):
            sent.update(kw)
            return types.SimpleNamespace(stop_reason="end_turn",
                                         content=[types.SimpleNamespace(type="text", text="ok")])
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    d.claude_translate(text, src, dst)
    return sent["messages"][0]["content"]


def test_claude_prompt_nennt_geschlecht_bei_thai_quelle(monkeypatch):
    assert "The Thai speaker is female" in _claude_body(monkeypatch, "ไปไหนคะ", "th", "en")
    assert "Thai speaker is" not in _claude_body(monkeypatch, "ไปไหน", "th", "en")


# ---- 67: "repeat" langer Sätze ohne neue Anfrage ------------------------------------------------------------

def test_langer_satz_bleibt_fuer_repeat(monkeypatch):
    monkeypatch.setattr(d, "TTS_LAST", {"key": None, "data": None})
    monkeypatch.setattr(d.EdgeStream, "_request", lambda self: pytest.fail("keine neue Anfrage"))
    text = "x" * (d.TTS_CACHE_CHARS + 50)
    d._tts_last_put(("Voice", 0, text), b"mp3")
    st = d.EdgeStream(text, "Voice", 0)
    assert st.cached == b"mp3" and st.audio.is_set()


def test_tts_last_grenze(monkeypatch):
    monkeypatch.setattr(d, "TTS_LAST", {"key": None, "data": None})
    d._tts_last_put(("v", 0, "t"), b"x" * (d.TTS_LAST_BYTES + 1))
    assert d.TTS_LAST["key"] is None


def test_clear_leert_auch_tts_last():
    i = SRC.index("TTS_CACHE.clear()")
    assert 'TTS_LAST["key"] = TTS_LAST["data"] = None' in SRC[i:i + 200]


# ---- 69: Ausreden lassen ------------------------------------------------------------------------------------

def test_wait_quiet_ohne_let_finish_sofort(monkeypatch):
    monkeypatch.setitem(d.LET_FINISH, "s", 0.0)
    d.HEARING.clear()
    assert d.wait_quiet() < 0.05


def test_wait_quiet_wartet_ruhe_ab_und_beginnt_neu(monkeypatch):
    monkeypatch.setitem(d.LET_FINISH, "s", 0.3)
    monkeypatch.setattr(d, "BARGE_IN", False)
    d.HEARING.clear()
    t1 = threading.Timer(0.1, d.HEARING.set)
    t2 = threading.Timer(0.25, d.HEARING.clear)
    t1.start()
    t2.start()
    try:
        waited = d.wait_quiet(limit=3.0)
    finally:
        t1.join()
        t2.join()
        d.HEARING.clear()
    assert 0.5 <= waited < 1.5          # 0,25 s bis wieder still + 0,3 s Ruhe


def test_wait_quiet_grenze_bleibt(monkeypatch):
    monkeypatch.setitem(d.LET_FINISH, "s", 5.0)
    monkeypatch.setattr(d, "BARGE_IN", False)
    d.HEARING.clear()
    assert d.wait_quiet(limit=0.2) < 0.4


# ---- 70: Latenz-Statistik -----------------------------------------------------------------------------------

def test_lat_summary(monkeypatch):
    monkeypatch.setattr(d, "LAT", {k: d.collections.deque(maxlen=d.LAT_N) for k in ("stt", "tr", "sound")})
    for v in range(1, 11):
        d.lat_add("sound", v / 10)
    d.lat_add("stt", 0.5)
    d.lat_add("tr", float("nan"))
    d.lat_add("tr", -1)
    assert d.lat_summary() == {"sound": {"n": 10, "p50": 0.5, "p90": 0.9}, "stt": {"n": 1, "p50": 0.5, "p90": 0.5}}


def test_state_enthaelt_latenz_und_neue_schalter():
    body = SRC[SRC.index("def emit_snapshot"):SRC.index("def _hotwords")]
    for k in ("latency=lat_summary()", "let_finish=", "catch_up=", "beam="):
        assert k in body


def test_deliver_misst_latenz_nur_fuer_mikrofon():
    body = SRC[SRC.index("    def deliver(self"):SRC.index('        emit("utt", to=dst, out=out, tr=round')]
    assert 'if source == "mic":' in body and 'lat_add("tr", tr_s)' in body


# ---- 171 / 176 / 69: Steuerfelder ---------------------------------------------------------------------------

def test_steuerfelder_runde6(ev, monkeypatch):
    monkeypatch.setitem(d.LET_FINISH, "s", 0.0)
    monkeypatch.setitem(d.CATCH_UP, "mode", "skip")
    eng = _eng()
    d.apply_control(eng, {"let_finish": 9, "catch_up": "fast", "beam": 3})
    assert d.LET_FINISH["s"] == d.LET_FINISH_MAX and d.CATCH_UP["mode"] == "fast" and eng.beam == 3
    d.apply_control(eng, {"let_finish": "x", "catch_up": "nie", "beam": 99})
    assert d.LET_FINISH["s"] == d.LET_FINISH_MAX and d.CATCH_UP["mode"] == "fast" and eng.beam == 5
    eng.beam_default = 2
    d.apply_control(eng, {"beam": 0})                   # „Automatisch“: zurück zum Startwert
    assert eng.beam == 2
    assert not [e for e, _ in ev if e == "control_ignored"]
    assert {"let_finish", "catch_up", "beam"} <= d.CTRL_KEYS & d.CTRL_LOG_KEYS


@pytest.mark.parametrize("mode, behind, boost", [("skip", 1, 20), ("fast", 1, 20), ("off", 1, 0), ("skip", 0, 0)])
def test_catch_up_tempo(monkeypatch, mode, behind, boost):
    monkeypatch.setitem(d.CATCH_UP, "mode", mode)
    monkeypatch.setitem(d.SLOW, "on", False)
    sp = types.SimpleNamespace(eng=types.SimpleNamespace(rate=0), FAST_BOOST=d.Speaker.FAST_BOOST)
    assert d.Speaker.boost(sp, behind) == boost


def test_catch_up_ueberspringt_nur_bei_skip():
    assert 'and CATCH_UP["mode"] == "skip"' in SRC


def test_startargumente_runde6():
    for opt in ("--let-finish", "--catch-up", "--beam"):
        assert f'"{opt}"' in SRC
    assert "eng.beam = max(1, min(5, a.beam))" in SRC


# ---- 74: Hedge aus gemessener Claude-Dauer ------------------------------------------------------------------

def test_hedge_adaptiv(monkeypatch):
    monkeypatch.setitem(d.LLM, "hedge_s", None)
    monkeypatch.setitem(d.LLM, "model", "claude-haiku-5-5")
    monkeypatch.setattr(d, "_LLM_DUR", {"model": None, "d": d.collections.deque(maxlen=d.HEDGE_N)})
    base = d.HEDGE_S["claude-haiku-5-5"]
    for _ in range(d.HEDGE_MIN_N - 1):
        d.llm_duration(0.5)
    assert d._hedge_s() == base                         # zu wenige Messungen
    d.llm_duration(0.5)
    assert d._hedge_s() == d.HEDGE_MIN                  # schnell: nicht unter HEDGE_MIN
    for _ in range(d.HEDGE_N):
        d.llm_duration(10.0)
    assert d._hedge_s() == round(base * 1.5, 2)         # langsam: höchstens 1,5 × Modellwert
    d.llm_duration(1.0, "claude-sonnet-5-5")            # Modellwechsel beginnt neu
    assert d._hedge_s() == base
    monkeypatch.setitem(d.LLM, "hedge_s", 2.7)
    assert d._hedge_s() == 2.7                          # feste Vorgabe gewinnt


# ---- 81: DOLMETSCHER_TUNE -----------------------------------------------------------------------------------

def test_apply_tuning(monkeypatch):
    for k in d.TUNABLE:
        monkeypatch.setattr(d, k, getattr(d, k))
    done = d.apply_tuning("min_utt=0.4, MAX_UTT=99, FOO=1, HEDGE=abc, MIN_LANG_P=nan")
    assert done == {"MIN_UTT": 0.4, "MAX_UTT": 30.0}
    assert d.MIN_UTT == 0.4 and d.MAX_UTT == 30.0
    assert d.apply_tuning("") == {}


# ---- 177: gleiche Normalisierung beim Anlegen ---------------------------------------------------------------

def test_enroll_audio_wird_normalisiert():
    a = (np.sin(np.linspace(0, 400, d.SR)) * 0.01).astype(np.float32)
    out = d.enroll_audio(a)
    assert np.allclose(out, d.normalize(a)[0]) and np.sqrt(np.mean(out ** 2)) > 0.03
    assert d.enroll_audio(None) is None
    assert "enroll_audio(record_one(a.mic))" in SRC


# ---- 181: Frage ohne „?“ ------------------------------------------------------------------------------------

@pytest.mark.parametrize("text, lang, q", [
    ("Where is the toilet", "en", True), ("How much is this", "en", True), ("Do you have water", "en", True),
    ("Can I pay by card", "en", True), ("Excuse me, where is the station", "en", True),
    ("What time does it open", "en", True), ("Is it far.", "en", True), ("Ok?", "en", True),
    ("When I was young I lived there", "en", False), ("How nice to meet you", "en", False),
    ("What a day", "en", False), ("Do it now", "en", False), ("I am fine", "en", False),
    ("Where is it!", "en", False), ("Wo ist das Klo", "de", False), ("Wo ist das Klo?", "de", True),
])
def test_is_question(text, lang, q):
    assert d.is_question(text, lang) is q


def test_fix_thai_nutzt_is_question():
    assert 'question=lang != "th" and is_question(text, lang)' in SRC


# ---- 205/206: Verlauf mit Sprechbeginn, Rolle und Profil ----------------------------------------------------

def test_migration_v1_auf_v2(tmp_path):
    import sqlite3
    p = tmp_path / "h.sqlite"
    db = sqlite3.connect(p)
    db.execute("""CREATE TABLE utt (id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT, ts REAL NOT NULL,
               session TEXT NOT NULL, lang TEXT, text TEXT, translation TEXT, translit TEXT, conf REAL,
               provider TEXT)""")
    db.execute("INSERT INTO utt (ts, session, lang, text) VALUES (1, 's', 'en', 'alt')")
    db.execute("PRAGMA user_version = 1")
    db.commit()
    db.close()
    st = hs.Store(str(p))
    assert st.db.execute("PRAGMA user_version").fetchone()[0] == 2
    assert {"t_begin", "role", "speaker"} <= {r[1] for r in st.db.execute("PRAGMA table_info(utt)")}
    assert st.rows()[0]["text"] == "alt" and st.rows()[0]["role"] is None
    st.close()
    hs.Store(str(p)).close()                           # zweiter Start: keine doppelte Spalte


def test_recorder_speichert_rolle_und_beginn(tmp_path, monkeypatch):
    rec = hs.Recorder()
    rec.store, rec.on = hs.Store(str(tmp_path / "h.sqlite")), True
    monkeypatch.setattr(hs.time, "time", lambda: 1000.0)
    rec.utt({"text": "Hello", "out": "สวัสดี", "translated": True, "lang": "en", "id": "u1", "role": "me",
             "speaker": "Pat", "ready_s": 1.0, "dur": 2.0})
    rec.utt({"text": "ครับ", "lang": "th", "id": "u2", "role": "egal", "speaker": 5, "dur": float("nan")})
    r1, r2 = rec.store.rows()
    assert (r1["t_begin"], r1["role"], r1["speaker"]) == (997.0, "me", "Pat")
    assert (r2["t_begin"], r2["role"], r2["speaker"]) == (None, None, None)


def test_untertitel_nutzen_sprechbeginn():
    rows = [{"ts": 110.0, "t_begin": 104.0, "session": "s", "text": "a", "translation": None},
            {"ts": 112.0, "t_begin": 110.5, "session": "s", "text": "b", "translation": None}]
    srt = hs.export(rows, "srt")
    assert "00:00:00,000 --> 00:00:01,500\na" in srt and "00:00:06,500 -->" in srt
    rows[0]["t_begin"] = 200.0                       # unplausibel (nach ts): ts gilt
    assert hs._start(rows[0]) == 110.0


def test_export_wer_hat_was_gesagt():
    rows = [{"ts": 1.0, "session": "s", "lang": "en", "text": "Hi", "translation": "ดี", "translit": None,
             "conf": None, "provider": None, "role": "me", "speaker": None},
            {"ts": 2.0, "session": "s", "lang": "th", "text": "ดี", "translation": "Hi", "translit": None,
             "conf": None, "provider": None, "role": "other", "speaker": "Ploy"}]
    md = hs.export(rows, "md")
    assert "[EN · ich] Hi" in md and "[TH · Ploy] ดี" in md
    assert hs.export(rows, "csv").splitlines()[0].endswith("provider,role,speaker")
    j = json.loads(hs.export(rows, "json"))
    assert j[0]["role"] == "me" and "speaker" not in j[0] and j[1]["speaker"] == "Ploy"


def test_utt_traegt_dauer():
    assert 'extra={"dur": round(audio.size / SR, 2)}' in SRC


# ---- 221: process liest self.spk nur einmal -----------------------------------------------------------------

def test_process_nutzt_lokale_profilkopie():
    body = SRC[SRC.index("    def process(self"):SRC.index("    def _speaker_polite")]
    assert "self.spk." not in body and 'spk = getattr(self, "spk", None)' in body
    learn = SRC[SRC.index("    def _learn_auto"):SRC.index("    def _remember")]
    assert "self.spk." not in learn


def test_learn_auto_ohne_profile_still():
    d.Engine._learn_auto(types.SimpleNamespace(spk=None), "me", {"role_how": "profil ich", "sim_me": 0.99},
                         10.0, "E")


# ---- 243: Preset-Hotwords und Ton-Hinweis -------------------------------------------------------------------

def _preset(**kw):
    p = {"id": "arzt", "names": {"de": "Arzt", "en": "Doctor", "th": "หมอ"}, "style": "neutral"}
    p.update(kw)
    return p


def test_preset_validiert_hotwords_und_hint():
    assert P.validate(_preset(hotwords=["Paracetamol", "ยาพารา"], llm_hint="precise medical terms")) == []
    assert P.validate(_preset(hotwords="x"))
    assert P.validate(_preset(hotwords=["x"] * (P.MAX_HOTWORDS + 1)))
    assert P.validate(_preset(llm_hint=""))
    assert P.validate(_preset(llm_hint="x" * (P.MAX_HINT + 1)))


def test_preset_hotwords_und_hint_wirken(monkeypatch):
    st = P.PresetState()
    monkeypatch.setattr(d, "PRESET", st)
    eng = types.SimpleNamespace(polite="krub", voices={})
    st.activate("arzt", {"arzt": _preset(hotwords=["Paracetamol", "ยาพารา"], llm_hint="Be precise.")},
                [], {"style": "casual"}, eng)
    assert "Paracetamol" in d.glossary_hotwords("en") and "ยาพารา" not in d.glossary_hotwords("en")
    assert "ยาพารา" in d.glossary_hotwords("th")
    assert "Scenario hint for this conversation (tone and terminology): Be precise." in _claude_body(
        monkeypatch, "Hello", "en", "th")
    st.activate(None, {}, [], {"style": "casual"}, eng)
    assert st.hotwords == [] and st.hint is None


# ---- 402: Fehlercode statt Logsuche -------------------------------------------------------------------------

def test_env_broken_meldet_code_und_endet(ev):
    with pytest.raises(SystemExit) as ex:
        d.env_broken(ModuleNotFoundError("No module named 'ctranslate2'", name="ctranslate2"))
    assert ex.value.code == 3
    assert ev == [("error", {"code": "python_env_broken", "module": "ctranslate2",
                             "msg": "Python-Umgebung unvollständig: Modul ctranslate2 fehlt"})]


def test_main_faengt_importfehler_beim_laden():
    i = SRC.index("    try:\n        eng = Engine(model")
    assert "except ImportError as e:\n        env_broken(e)" in SRC[i:i + 250]


# ---- 197: __main__ als Unterprozess (Argumente, Exit-Codes) -------------------------------------------------

def _run(args, tmp_path):
    env = dict(os.environ, DOLMETSCHER_HOME=str(tmp_path), DOLMETSCHER_LOG=str(tmp_path / "engine.log"),
               PYTHONIOENCODING="utf-8")
    return subprocess.run([sys.executable, "-B", str(ROOT / "dolmetscher.py"), *args], input="",
                          capture_output=True, text=True, timeout=90, env=env, cwd=str(tmp_path))


@pytest.mark.timeout(120)
def test_main_profiles_leer(tmp_path):
    r = _run(["--profiles", "--json"], tmp_path)
    assert r.returncode == 0, r.stderr[-500:]
    assert {"event": "profiles", "profiles": []} in [json.loads(x) for x in r.stdout.splitlines()
                                                    if x.startswith("{")]


@pytest.mark.timeout(120)
def test_main_history_export_leer(tmp_path):
    r = _run(["--history-export", "md"], tmp_path)
    assert r.returncode == 0, r.stderr[-500:]
    assert r.stdout.startswith("# Gesprächsverlauf")
    assert (tmp_path / "history.sqlite").exists()


@pytest.mark.timeout(120)
def test_main_unbekanntes_argument(tmp_path):
    r = _run(["--gibtsnicht"], tmp_path)
    assert r.returncode == 2 and "--gibtsnicht" in r.stderr
