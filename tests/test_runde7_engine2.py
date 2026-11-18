"""Runde 7, zweiter Teil (Engine): Mikrofon, Ausgabe-Pipe, Verlauf asynchron/WAL, Hilfsprozesse."""
import queue
import sqlite3
import types

import pytest

import dolmetscher as d
import history_store as hs


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def test_reconnect_wechselt_nie_still_aufs_standardmikrofon(monkeypatch, ev):
    monkeypatch.setattr(d, "list_mics", lambda: [{"index": "1", "name": "Raum"}])
    assert d.resolve_mic("AirPods", strict=True) is None and not ev
    assert d.resolve_mic("AirPods") == "default" and ev[0][1]["code"] == "mic_not_found"
    assert d.resolve_mic("Raum", strict=True) == "1"


def test_start_im_reconnect_wartet_aufs_geraet(monkeypatch, ev):
    m = d.Mic.__new__(d.Mic)
    m.mic, m.idle, m.jobs = "AirPods", True, queue.Queue()
    monkeypatch.setattr(d, "list_mics", lambda: [])
    monkeypatch.delenv("DOLMETSCHER_MIC_FILE", raising=False)
    assert m.start(_retry=True) is False
    assert not [e for e in ev if e[0] == "error"]            # leise: nächster Versuch folgt


def test_net_llm_mit_retry_zeit(monkeypatch, ev):
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setitem(d.LLM, "billing_told", False)
    monkeypatch.setitem(d.NET, "llm", True)
    d._llm_failed(TimeoutError("x"))
    net = [k for e, k in ev if e == "net"]
    assert net and net[0]["what"] == "llm" and net[0]["ok"] is False and net[0]["retry_in_s"] > 0


def test_ausgabe_pipe_opfert_zuerst_pegelzeilen(monkeypatch):
    q = queue.Queue(maxsize=3)
    monkeypatch.setitem(d._OUT, "q", q)
    monkeypatch.setitem(d._OUT, "dropped", 0)
    for line in ('{"event": "heard", "id": 1}', '{"event": "level", "rms": 0.1}', '{"event": "utt", "id": 1}'):
        q.put_nowait(line)
    d._enqueue("error", '{"event": "error"}')
    assert list(q.queue) == ['{"event": "heard", "id": 1}', '{"event": "utt", "id": 1}', '{"event": "error"}']


def test_ws_oeffnen_pausiert_nach_fehlschlaegen(monkeypatch):
    import asyncio
    calls = []

    async def boom():
        calls.append(1)
        raise OSError("kein Netz")
    monkeypatch.setattr(d, "_ws_open", boom)
    tasks = []
    monkeypatch.setattr(d, "_spawn", lambda coro: tasks.append(asyncio.ensure_future(coro)))
    monkeypatch.setitem(d._WS, "pool", [])
    monkeypatch.setitem(d._WS, "opening", 0)
    monkeypatch.setattr(d, "_WS_OPEN", {"fails": 0, "pause_until": 0.0})
    monkeypatch.setattr(d, "WS_POOL_N", 4)
    async def fill():
        await d._ws_fill()
        await asyncio.gather(*tasks)
    asyncio.run(fill())
    n = len(calls)
    asyncio.run(fill())
    assert len(calls) == n and d._WS_OPEN["pause_until"] > 0          # Pause: keine neuen Versuche


def test_offline_mt_leerlauf_beendet_helfer():
    mt = d.OfflineMT()
    killed = []
    mt.proc = types.SimpleNamespace(kill=lambda: killed.append(1))
    mt.last_used = 100.0
    assert not mt.close_if_idle(now=150.0) and mt.proc is not None
    assert mt.close_if_idle(now=100.0 + mt.IDLE_CLOSE_S + 1) and killed and mt.proc is None


def test_dateimodus_ohne_ueberspringen_im_quelltext():
    src = open(d.__file__, encoding="utf-8").read()
    assert 'CATCH_UP["mode"] = "off"' in src and "wait_idle(timeout=6 * 3600)" in src


def test_verlauf_async_schreibt_ausserhalb_und_flush(tmp_path):
    rec = hs.Recorder()
    rec.store, rec.on, rec.async_mode = hs.Store(str(tmp_path / "h.sqlite")), True, True
    for i in range(20):
        rec.utt({"text": f"t{i}", "out": "x", "translated": True, "lang": "en", "id": f"u{i}"})
    rec.flush()
    assert len(rec.store.rows()) == 20
    rec.enable(False)
    rec.utt({"text": "nach aus"})
    rec.flush()
    assert len(rec.store.rows()) == 20


def test_verlauf_wal_und_checkpoint_nach_loeschen(tmp_path):
    st = hs.Store(str(tmp_path / "h.sqlite"))
    assert st.db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
    st.add("geheimer text", "x", lang="en", session="s")
    st.clear()
    st.close()
    wal = tmp_path / "h.sqlite-wal"
    assert not wal.exists() or wal.stat().st_size == 0
    assert b"geheimer text" not in (tmp_path / "h.sqlite").read_bytes()
    assert sqlite3.connect(str(tmp_path / "h.sqlite")).execute("select count(*) from utt").fetchone()[0] == 0


# ---- Teil 3: Anrede, Fragen, Cache auf Platte, Zahlen, Download ---

def test_register_hint_nach_stil():
    assert "du" in d.register_hint("de", "casual") and "Sie" in d.register_hint("de", "polite")
    assert "usted" in d.register_hint("es", "neutral")
    assert d.register_hint("en", "casual") == ""


@pytest.mark.parametrize("lang,text,want", [("de", "Wo ist die Toilette", True), ("de", "Ich bin müde", False),
                                            ("es", "Dónde está el baño", True), ("fr", "Où est la gare", True),
                                            ("de", "Wie schön!", False)])
def test_frage_ohne_fragezeichen_weitere_sprachen(lang, text, want):
    assert d.is_question(text, lang) is want


def test_cache_auf_platte_opt_in(monkeypatch, tmp_path):
    f = tmp_path / "c.json"
    monkeypatch.setattr(d, "CACHE_FILE", str(f))
    monkeypatch.setattr(d, "_CACHE_DISK", {"on": False, "saved": 0.0})
    d._cache_clear()
    d._cache_put(("hello", "en", "de", "mt", ""), ("hallo", "google"))
    assert not f.exists()                                     # Standard: nichts auf der Platte
    d.cache_persist(True)
    d._cache_put(("how are you", "en", "de", "mt", ""), ("wie geht's", "google"))
    assert f.exists() and oct(f.stat().st_mode & 0o777) == "0o600"
    d._cache_clear()                                          # "clear" löscht auch die Datei
    assert not f.exists()
    d._cache_put(("thanks", "en", "de", "mt", ""), ("danke", "google"))
    d._cache_save(force=True)
    d._CACHE.clear()
    d.cache_persist(True)                                     # "Neustart": aus der Datei laden
    assert d._cache_get(("thanks", "en", "de", "mt", "")) == ("danke", "google")
    d.cache_persist(False)
    assert not f.exists() and not d._CACHE_DISK["on"]
    d._cache_clear()


def test_cache_persist_steuerfeld(monkeypatch, ev):
    seen = []
    monkeypatch.setattr(d, "cache_persist", lambda v: seen.append(v))
    d.apply_control(types.SimpleNamespace(voices={}, translate_dir={}), {"cache_persist": True})
    assert seen == [True] and not [k for e, k in ev if e == "control_ignored"]


def test_num_diff_nennt_die_abweichenden_zahlen():
    det = d._numbers_detail("It costs 200 baht", "ราคา 300 บาท")
    assert det == {"src": ["200"], "out": ["300"]}


def test_download_zaehlt_nur_neue_dateien(tmp_path):
    import os
    import time
    old = tmp_path / "alt"
    old.write_bytes(b"\0" * 1000)
    os.utime(old, (time.time() - 3600, time.time() - 3600))
    t0 = time.time()
    (tmp_path / "neu").write_bytes(b"\0" * 500)
    assert d._dir_bytes_since(str(tmp_path), t0) == 500


def test_set_pair_wird_nie_leer(monkeypatch):
    seen = []
    monkeypatch.setattr(d, "PAIR", ["en", "th"])
    monkeypatch.setattr(d, "TARGET", {"en": "th", "th": "en"})
    orig = d.parse_pair
    monkeypatch.setattr(d, "parse_pair", lambda a, b: orig(a, b))

    class Spy(dict):
        def update(self, *a, **k):
            super().update(*a, **k)
            seen.append(dict(self))
    monkeypatch.setattr(d, "TARGET", Spy({"en": "th", "th": "en"}))
    assert d.set_pair("de", "ja")
    assert d.TARGET == {"de": "ja", "ja": "de"} and all(seen)
    d.set_pair("en", "th")


def test_alte_tmp_dateien_werden_aufgeraeumt(tmp_path, monkeypatch):
    import os
    import time
    stale = tmp_path / ".tmp_alt"
    stale.write_text("x")
    os.utime(stale, (time.time() - 3 * 86400,) * 2)
    fresh = tmp_path / ".tmp_neu"
    fresh.write_text("x")
    monkeypatch.setattr(d, "_TMP_CLEANED", set())
    d._write_private(str(tmp_path / "g.txt"), "hi")
    assert not stale.exists() and fresh.exists()


def test_glossar_lernen_schaltet_preset_im_fehlerfall_wieder_an(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "set_preset", lambda eng, pid, quiet=False: calls.append(pid))
    monkeypatch.setattr(d.PRESET, "active", "hotel", raising=False)
    monkeypatch.setattr(d, "load_glossary", lambda t: (_ for _ in ()).throw(OSError("voll")))
    with pytest.raises(OSError):
        d.learn_glossary_names(object(), ["Neuname"])
    assert calls == [None, "hotel"]


# ---- Teil 4: Hinweise, Tuning, Untertitel, Suche, Akku ---

def test_tuning_je_szenario_setzen_und_zurueck(monkeypatch):
    monkeypatch.setattr(d, "SILENCE_END", 0.7)
    monkeypatch.setattr(d, "_TUNING_SAVED", {})
    monkeypatch.setitem(d.LET_FINISH, "s", 0.0)
    monkeypatch.setitem(d.CATCH_UP, "mode", "skip")
    e = types.SimpleNamespace(rate=0)
    p = {"tuning": {"silence": 1.5, "let_finish": 1.0, "catch_up": "off", "rate": -20, "sensitivity": "high"}}
    d._apply_preset_tuning(e, p)
    assert d.SILENCE_END == 1.5 and d.LET_FINISH["s"] == 1.0 and d.CATCH_UP["mode"] == "off" and e.rate == -20
    d._apply_preset_tuning(e, None)
    assert d.SILENCE_END == 0.7 and d.LET_FINISH["s"] == 0.0 and d.CATCH_UP["mode"] == "skip" and e.rate == 0


def test_preset_tuning_wird_validiert():
    import presets as P
    base = {"id": "t", "names": {"de": "T", "en": "T", "th": "T"}, "style": "casual"}
    assert P.validate({**base, "tuning": {"silence": 1.0, "catch_up": "fast"}}) == []
    assert P.validate({**base, "tuning": {"silence": 99}})
    assert P.validate({**base, "tuning": {"unbekannt": 1}})
    assert P.validate({**base, "tuning": {"sensitivity": "extrem"}})


def test_tunable_klassenwerte(monkeypatch):
    monkeypatch.setattr(d.Speaker, "SKIP_AT", 3)
    done = d.apply_tuning("SKIP_AT=5,WAKE_S=9,PRE_AT=99")
    assert d.Speaker.SKIP_AT == 5 and done["WAKE_S"] == 9.0 and done["PRE_AT"] == 1.5
    d.Speaker.SKIP_AT = 3


def test_hint_selten_und_langsam_erkannt(monkeypatch, ev):
    monkeypatch.setattr(d, "_HINT_T", {})
    for _ in range(10):
        d.lat_add("sound", 9.0)
    hints = [k for e, k in ev if e == "hint"]
    assert len(hints) == 1 and hints[0]["code"] == "slow" and hints[0]["what"] == "sound"
    for k in d.LAT:
        d.LAT[k].clear()


def test_mikrofon_zu_leise_hinweis(monkeypatch, ev):
    monkeypatch.setattr(d, "_HINT_T", {})
    monkeypatch.setattr(d, "_SHORTS", d.collections.deque(maxlen=6))
    for _ in range(6):
        d._note_short(0.005)
    assert [k["code"] for e, k in ev if e == "hint"] == ["mic_far"]


def test_ersatzstimme_wird_einmal_gemeldet(monkeypatch, ev):
    monkeypatch.setattr(d, "_TTS_FB", {"on": False})
    d._tts_fallback("offline")
    d._tts_fallback("slow")
    assert [k for e, k in ev if e == "tts_fallback"] == [{"reason": "offline"}]


def test_suche_mit_kontext_und_filter(tmp_path):
    import history_store as hs
    st = hs.Store(str(tmp_path / "h.sqlite"))
    for i, t in enumerate(["eins", "zwei Nadel", "drei", "vier"]):
        st.add(t, "x", lang="de" if i != 3 else "en", session="s", ts=10.0 + i)
    hit = st.search("Nadel", context=1)
    assert [c["text"] for c in hit[0]["context"]] == ["eins", "drei"]
    assert st.search("Nadel", lang="en") == []
    assert len(st.search("Nadel", lang="de")) == 1
    st.close()


def test_verlauf_ohne_sprechernamen(tmp_path):
    import history_store as hs
    rec = hs.Recorder()
    rec.store, rec.on, rec.store_speakers = hs.Store(str(tmp_path / "h.sqlite")), True, False
    rec.utt({"text": "hi", "speaker": "Patrick", "role": "me"})
    row = rec.store.rows()[0]
    assert row["speaker"] is None and row["role"] == "me"


def test_untertitel_aus_dateiposition(tmp_path, monkeypatch, ev):
    import history_store as hs
    monkeypatch.setattr(d, "private_tmp", lambda: str(tmp_path))
    monkeypatch.setattr(hs, "RECORDER", hs.Recorder())
    store = d._subtitle_recorder(str(tmp_path / "o.srt"))
    rec = hs.RECORDER
    rec.file_pos = 4.0
    rec.utt({"text": "Hello", "out": "Hallo", "translated": True, "lang": "en", "dur": 2.0, "ready_s": 30.0})
    rec.file_pos = 9.0
    rec.utt({"text": "Bye", "out": "Tschüss", "translated": True, "lang": "en", "dur": 1.0, "ready_s": 30.0})
    d._write_subtitles(store, str(tmp_path / "o.srt"))
    srt = (tmp_path / "o.srt").read_text(encoding="utf-8")
    assert "00:00:00,000 --> " in srt and "00:00:06,000 --> " in srt and "Hallo" in srt
    assert [k for e, k in ev if e == "subtitles"][0]["cues"] == 2


def test_akku_spart(monkeypatch):
    import hwprofile
    rec = {"model": "best", "beam": 5, "reason": "x"}
    out = hwprofile.adjust_for_power(rec, True)
    assert out["model"] == "medium" and out["beam"] == 1 and hwprofile.adjust_for_power(rec, False) == rec
    run = lambda cmd, **k: types.SimpleNamespace(stdout="Now drawing from 'Battery Power'")  # noqa: E731
    assert hwprofile.on_battery(run) is True


def test_say_modus_rendert_vorab():
    src = open(d.__file__, encoding="utf-8").read()
    assert 'elif eng.tts == "say" and not eng.mute' in src


# ---- Teil 5: Privatmodus, Anki, Hotwords, Notfall-Phrasen, Schema ---

def test_privatmodus_laedt_kein_sprechermodell(tmp_path, monkeypatch):
    import profiles
    monkeypatch.setattr(profiles, "MODEL_PATH", str(tmp_path / "m" / "model.onnx"))
    monkeypatch.setattr(profiles, "OFFLINE_ONLY", True)
    monkeypatch.setattr(profiles, "_download", lambda *a, **k: (_ for _ in ()).throw(AssertionError("Download!")))
    with pytest.raises(RuntimeError, match="speaker model unavailable"):
        profiles.ensure_model()


def test_hotword_budget_gewichtet_thai():
    import profiles
    p = {"name": "T", "lang": "th", "vocab": ["ตลาดน้ำอัมพวา" for _ in range(1)] + [f"คำ{i}ยาวมากๆ" for i in range(60)]}
    out = profiles.pick_hotwords([p], "th")
    assert out.split()[0] == "ตลาดน้ำอัมพวา" and sum(3 if "฀" <= c <= "๿" else 1 for c in out) <= 400 + 60


def test_learn_ersetzt_nur_ein_profil_im_speicher(monkeypatch):
    import numpy as np
    import profiles
    s = profiles.SpeakerID.__new__(profiles.SpeakerID)
    a = {"name": "A", "embedding": [1.0, 0.0]}
    b = {"name": "B", "embedding": [0.0, 1.0]}
    s.profiles, s._emb = [a, b], {"A": np.array([1.0, 0.0], np.float32), "B": np.array([0.0, 1.0], np.float32)}
    s.mat = np.stack([s._emb["A"], s._emb["B"]])
    s._reload = lambda: (_ for _ in ()).throw(AssertionError("voller Neuaufbau"))
    s.reload = s._reload
    s._reload_one({"name": "A", "embedding": [0.8, 0.6]})
    assert s.profiles[1] is b and s.profiles[0]["embedding"] == [0.8, 0.6]
    assert abs(float(np.linalg.norm(s.mat[0])) - 1.0) < 1e-5 and s._state[2] is s.mat


def test_localvoice_cleanup_ohne_wartethread(monkeypatch, tmp_path):
    import os
    monkeypatch.setattr(d, "private_tmp", lambda: str(tmp_path))
    monkeypatch.setattr(d, "say_cmd", lambda voice, rate, path, text: ["x", path])

    def fake_run(cmd, cancelled=None):
        open(cmd[1], "wb").write(b"ok")
        return 0
    monkeypatch.setattr(d, "run_cancellable", fake_run)
    lv = d.LocalVoice("hi", "Samantha", 0)
    assert lv.done.wait(5) and os.path.exists(lv.path)
    before = d.threading.active_count()
    lv.cleanup()
    assert not os.path.exists(lv.path) and d.threading.active_count() <= before


def test_notfall_phrasen_werden_vorab_gerendert(monkeypatch):
    seen = []
    monkeypatch.setattr(d, "edge_prerender", lambda text, voice, rate: seen.append((text, voice, rate)) or True)
    eng = types.SimpleNamespace(tts="edge", mute=False, rate=0, voice_for=lambda lang: f"v-{lang}")
    monkeypatch.setitem(d.PRIVATE, "on", False)
    monkeypatch.setitem(d.NET, "tts", True)
    preset = {"phrases": [{"en": "I am allergic to nuts", "th": "ฉันแพ้ถั่ว", "critical": True},
                          {"en": "Hello", "th": "สวัสดี"}]}
    t = d.prerender_critical(eng, preset)
    t.join(5)
    assert {s[1] for s in seen} == {"v-en", "v-th"} and all("Hello" not in s[0] for s in seen)
    assert d.prerender_critical(types.SimpleNamespace(tts="say", mute=False, rate=0), preset) is None
    monkeypatch.setitem(d.PRIVATE, "on", True)
    assert d.prerender_critical(eng, preset) is None                 # Privatmodus: kein Netz


def test_letzte_ausgabe_nach_neustart_aus_verlauf(tmp_path, monkeypatch):
    import history_store as hs
    rec = hs.Recorder()
    rec.store, rec.on = hs.Store(str(tmp_path / "h.sqlite")), True
    rec.store.add("Hello", "สวัสดี", lang="en", session="s", ts=5.0)
    monkeypatch.setattr(hs, "RECORDER", rec)
    e = d.Engine.__new__(d.Engine)
    e.last = None
    assert e.restore_last() and e.last[:2] == ("สวัสดี", "th")


def test_sprachtabelle_schema_pflichtfelder():
    import json
    import os
    data = json.load(open(os.path.join(os.path.dirname(d.__file__), "languages.json"), encoding="utf-8"))
    required = {"code", "names", "scripts", "locale", "edge", "macos", "min_logprob", "phrases"}
    optional_seen = set()
    for lang in data["languages"]:
        assert required <= set(lang), (lang["code"], required - set(lang))
        assert {"m", "f", "voices"} <= set(lang["edge"]) and {"voice", "locale"} <= set(lang["macos"])
        assert {"en", "de", "native"} <= set(lang["names"])
        optional_seen |= set(lang) - required
    assert optional_seen <= {"flag", "app_voices", "mt", "apple_translation"}, optional_seen


def test_keine_wiederholungssperre_fuer_doppelungssprachen():
    src = open(d.__file__, encoding="utf-8").read()
    assert 'NO_REP_PENALTY = frozenset({"zh", "ja", "ko", "id", "vi", "ms"})' in src
    assert "elif lang in NO_REP_PENALTY" in src
    assert {"zh", "ja", "ko", "id", "vi"} <= d.NO_REP_PENALTY and "en" not in d.NO_REP_PENALTY
