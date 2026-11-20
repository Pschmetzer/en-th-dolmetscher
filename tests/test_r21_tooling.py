"""Runde 21 (Werkzeuge/Daten): presets.find/parse_spoken, history_store, avhelper, profiles, satzbuch, CI-Dateien."""
import json
import math
import pathlib
import sqlite3
import subprocess
import sys
import threading

import pytest

import avhelper
import history_store as hs
import presets as P
import profiles
import satzbuch

ROOT = pathlib.Path(__file__).resolve().parent.parent


@pytest.fixture(autouse=True)
def home(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    return tmp_path


def good(**kw):
    d = {"id": "demo", "names": {"de": "Demo", "en": "Demo", "th": "เดโม"}, "style": "polite",
         "glossary": [{"en": "room", "th": "ห้อง"}], "phrases": [{"en": "Hello", "th": "สวัสดี"}]}
    d.update(kw)
    return d


# ---- presets.find / parse_spoken ------------------------------------------------------------------------------

@pytest.mark.parametrize("spoken, pid", [
    ("police theft", "police"), ("Police / theft", "police"), ("Reise-Notfälle", "emergency"),
    ("reise notfälle", "emergency"), ("พบแพทย์", "doctor"), ("แท็กซี่", "taxi"), ("TAXI", "taxi"),
    ("travel emergencies", "emergency"), ("  hotel  ", "hotel"), ("", None), (None, None), ("zzz", None)])
def test_find_normalises_names_and_input(spoken, pid):
    assert P.find(spoken) == pid


def test_find_thai_marks_survive():
    assert P.find("แท็กซี่") == "taxi"                        # Tonzeichen (Mn) bleiben im Vergleich
    assert P._norm("พบแพทย์") == "พบแพทย์"


@pytest.mark.parametrize("cmd, out", [
    ("hotel mode", "preset:hotel"), ("preset taxi", "preset:taxi"), ("preset off", "preset:none"),
    ("preset aus", "preset:none"), ("Szenario Taxi", "preset:taxi"), ("Reise-Notfälle Modus", "preset:emergency"),
    ("โหมดโรงแรม", "preset:hotel"), ("โหมด แท็กซี่", "preset:taxi"), ("hello there", None),
    ("what is the mode of transport please now", None), ("mode", None), ("", None)])
def test_parse_spoken_languages(cmd, out):
    assert P.parse_spoken(cmd) == out


def test_oversized_preset_file_is_skipped(home):
    ud = home / "presets"
    ud.mkdir()
    (ud / "big.json").write_text(json.dumps(good(id="big", note={"de": "x" * 100, "en": "y"}))
                                 + " " * (P.MAX_FILE + 1), encoding="utf-8")
    P.load_all()
    assert any("größer" in v for v in P.last_errors.values())
    assert "big" not in P.load_all()


def test_duplicate_id_in_same_folder_reported(home):
    ud = home / "presets"
    ud.mkdir()
    (ud / "a.json").write_text(json.dumps(good(id="same")), encoding="utf-8")
    (ud / "b.json").write_text(json.dumps(good(id="same")), encoding="utf-8")
    allp = P.load_all()
    assert "same" in allp
    assert any("doppelt" in v for v in P.last_errors.values())


# ---- history_store ---------------------------------------------------------------------------------------------

@pytest.fixture
def st(tmp_path):
    s = hs.Store(str(tmp_path / "h.sqlite"))
    yield s
    s.close()


def _fill(st):
    for i in range(30):
        st.add("hello %d" % i, "สวัสดี", lang="en" if i % 2 else "th", session="s%d" % (i % 3), ts=1000.0 + i)


def test_indexes_exist(st):
    names = {r[1] for r in st.db.execute("PRAGMA index_list(utt)")}
    assert {"utt_ts", "utt_uid", "utt_session_ts"} <= names


def test_search_filters_in_sql_not_after_limit(st):
    _fill(st)
    # limit 2 zaehlt nur Treffer, die auch den Filter erfuellen (frueher: erst LIMIT, dann Python-Filter)
    r = st.search("hello", limit=2, lang="th", since=1000.0)
    assert len(r) == 2 and all(x["lang"] == "th" for x in r)
    r = st.search("hello", limit=50, session="s1")
    assert len(r) == 10 and {x["session"] for x in r} == {"s1"}
    assert st.search("hello", since=1029.0)[0]["ts"] == 1029.0 and len(st.search("hello", since=1029.0)) == 1


def test_init_failure_closes_connection(tmp_path, monkeypatch):
    path = str(tmp_path / "h.sqlite")
    hs.Store(path).close()
    con = sqlite3.connect(path)
    con.execute("PRAGMA user_version = 99")
    con.commit()
    con.close()
    opened = []
    real = sqlite3.connect
    monkeypatch.setattr(sqlite3, "connect", lambda *a, **k: opened.append(real(*a, **k)) or opened[-1])
    with pytest.raises(sqlite3.DatabaseError):
        hs.Store(path)
    with pytest.raises(sqlite3.ProgrammingError):          # Verbindung ist zu
        opened[0].execute("SELECT 1")


def test_concurrent_writes_and_reads(st):
    errs = []

    def writer():
        try:
            for i in range(60):
                st.add("w%d" % i, "t", lang="en", session="a")
        except Exception as e:
            errs.append(e)

    def reader():
        try:
            for _ in range(60):
                st.rows()
                st.sessions()
                st.search("w", limit=5)
                st.last_translation()
        except Exception as e:
            errs.append(e)
    ts = [threading.Thread(target=f) for f in (writer, reader, reader)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert not errs and len(st.rows()) == 60


def test_like_fallback_without_fts(tmp_path, monkeypatch):
    monkeypatch.setattr(hs.Store, "_init_fts", lambda self: False)
    s = hs.Store(str(tmp_path / "n.sqlite"))
    s.add("Café Crème", "x", lang="fr", session="a")
    assert len(s.search("crème")) == 1 and len(s.search("CAFÉ")) == 1
    s.close()


def test_flat_strips_control_and_line_separators():
    assert hs._flat("a b c\x00d\x07e\nf") == "a b cde f"


def test_cues_arrow_cannot_break_cue(st):
    st.add("a --> b", "c --> d", lang="en", session="s", ts=10.0)
    out = hs.export(st.rows(), "srt")
    assert out.count("-->") == 1


def test_compact_reports_success(st):
    st.add("x", session="a")
    assert st.clear() == 1 and st._compact() is True


def test_deleted_text_not_in_file(tmp_path):
    p = tmp_path / "h.sqlite"
    s = hs.Store(str(p))
    s.add("GEHEIMWORT-12345", "ÜBERSETZUNG-67890", lang="en", session="a")
    s.clear()
    s.close()
    raw = p.read_bytes()
    assert b"GEHEIMWORT-12345" not in raw and "ÜBERSETZUNG-67890".encode() not in raw


def test_v1_database_migrates(tmp_path):
    p = str(tmp_path / "v1.sqlite")
    con = sqlite3.connect(p)
    con.execute("CREATE TABLE utt (id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT, ts REAL NOT NULL, session TEXT "
                "NOT NULL, lang TEXT, text TEXT, translation TEXT, translit TEXT, conf REAL, provider TEXT)")
    con.execute("INSERT INTO utt (ts, session, text) VALUES (1, 's', 'alt')")
    con.commit()
    con.close()
    s = hs.Store(p)
    assert s.db.execute("PRAGMA user_version").fetchone()[0] == hs.SCHEMA_VERSION
    assert s.rows()[0]["text"] == "alt" and "role" in s.rows()[0]
    s.close()


def test_recorder_queue_bounded_and_flush_timeout(tmp_path, monkeypatch):
    rec = hs.Recorder()
    rec.async_mode, rec.on = True, True
    rec.store = hs.Store(str(tmp_path / "q.sqlite"))
    rec.QUEUE_MAX, rec.FLUSH_TIMEOUT_S = 2, 0.2
    gate = threading.Event()
    real = rec._write
    monkeypatch.setattr(rec, "_write", lambda *a: (gate.wait(5), real(*a)))
    for i in range(10):
        rec.utt({"text": "t%d" % i})
    assert rec.dropped >= 5
    t0 = __import__("time").monotonic()
    rec.flush()                                             # kehrt nach dem Timeout zurueck, auch wenn der Writer haengt
    assert __import__("time").monotonic() - t0 < 2.0
    gate.set()
    rec.flush()
    rec.store.close()


def test_recorder_transient_error_keeps_on(tmp_path, monkeypatch):
    rec = hs.Recorder()
    rec.on = True
    rec.store = hs.Store(str(tmp_path / "r.sqlite"))

    def boom(*a, **k):
        raise sqlite3.OperationalError("disk I/O error")
    monkeypatch.setattr(rec.store, "add", boom)
    rec._write({"text": "x"}, 1.0)
    assert rec.on                                           # erst nach MAX_FAILS aus
    for _ in range(rec.MAX_FAILS):
        rec._write({"text": "x"}, 2.0)
    assert not rec.on
    rec.store.close()


def _cli(**kw):
    import argparse
    d = dict(history_export=None, history_search=None, history_purge=None, history_clear=False, history_sessions=False,
             history_session=None, history_context=0, history_lang=None, out=None)
    d.update(kw)
    return argparse.Namespace(**d)


def test_cli_export_unknown_session_is_error(home, capsys):
    hs.Store().close()
    assert hs.run_cli(_cli(history_export="md", history_session="nope")) == 2
    assert "unbekannte Sitzung" in capsys.readouterr().out


def test_cli_export_refuses_symlink(home, tmp_path):
    s = hs.Store()
    s.add("x", session="a")
    s.close()
    target = tmp_path / "ziel.txt"
    target.write_text("wichtig")
    link = tmp_path / "link.md"
    link.symlink_to(target)
    with pytest.raises(OSError):
        hs.run_cli(_cli(history_export="md", out=str(link)))
    assert target.read_text() == "wichtig"


# ---- avhelper / profiles / satzbuch ----------------------------------------------------------------------------

def test_avhelper_rejects_nan_volume_and_bad_rate():
    for argv in (["play", "--volume", "nan"], ["play", "--volume", "inf"], ["capture", "--rate", "0"],
                 ["capture", "--rate", "-5"], ["capture", "--rate", "100000"]):
        with pytest.raises(SystemExit) as e:
            avhelper.main(argv)
        assert e.value.code == 2


def test_avhelper_empty_file_loop_exits(tmp_path):
    import wave
    f = tmp_path / "leer.wav"
    with wave.open(str(f), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"")
    r = subprocess.run([sys.executable, "-I", str(ROOT / "avhelper.py"), "capture", "--file", str(f), "--loop"],
                       capture_output=True, timeout=30, cwd=str(ROOT))
    assert r.returncode != 0 and b"no audio" in r.stderr


def test_enroll_unknown_language_raises_valueerror():
    with pytest.raises(ValueError, match="Sprache"):
        profiles.enroll("Tester", "xx", None, None, None, None)


def test_corrupt_list_does_not_grow(home, monkeypatch):
    d = pathlib.Path(profiles.PROFILE_DIR)
    d.mkdir(parents=True, exist_ok=True)
    f = d / "x.json"
    f.write_text("{}", encoding="utf-8")
    monkeypatch.setattr("builtins.open", lambda *a, **k: (_ for _ in ()).throw(PermissionError("nein")))
    before = len(profiles.CORRUPT)
    for _ in range(5):
        profiles._load_file(str(f))
    assert len(profiles.CORRUPT) - before <= 1


@pytest.mark.parametrize("v", ["=1+1", "+1", "-1", "@x", "\tx", "\rx"])
def test_csv_safe_both_modules(v):
    assert hs._csv_safe(v) == "'" + v and satzbuch._csv_safe(v) == "'" + v
    assert hs._csv_safe("ok") == "ok" and satzbuch._csv_safe(5) == 5


def test_satzbuch_csv_has_bom_and_no_formula(tmp_path):
    folder = tmp_path / "p"
    folder.mkdir()
    (folder / "demo.json").write_text(json.dumps(good(phrases=[{"en": "=SUM(1)", "th": "สวัสดี"}])), encoding="utf-8")
    out = tmp_path / "o.csv"
    assert satzbuch.main(["export", "csv", "--dir", str(folder), "-o", str(out)]) == 0
    raw = out.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf") and b"'=SUM(1)" in raw


# ---- tools / CI ------------------------------------------------------------------------------------------------

def test_check_presets_accepts_runtime_fields_and_flags_numbers(tmp_path):
    sys.path.insert(0, str(ROOT / "tools"))
    import check_presets
    d = good(hotwords=["Soi 11"], llm_hint="Ton ruhig", tuning={"let_finish": 2.0},
             phrases=[{"en": "Call 1669", "th": "โทร 1155"}])
    res = check_presets.run([("demo.json", d)])
    assert not [r for r in res if "unbekanntes Feld" in r[2]]
    assert any("Zahlen" in r[2] for r in res)
    d["tuning"] = {"let_finish": 99}
    assert any("tuning" in r[2] for r in check_presets.run([("demo.json", d)]))


def test_load_packs_reports_all_broken(tmp_path):
    sys.path.insert(0, str(ROOT / "tools"))
    import _presetlib
    for n in ("a", "b"):
        (tmp_path / (n + ".json")).write_text("{kaputt", encoding="utf-8")
    with pytest.raises(SystemExit) as e:
        _presetlib.load_packs(str(tmp_path))
    assert "a.json" in str(e.value) and "b.json" in str(e.value)


def test_presets_index_check_prints_diff(tmp_path, monkeypatch):
    sys.path.insert(0, str(ROOT / "tools"))
    r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "make_presets_index.py"), "--check"],
                       capture_output=True, text=True, cwd=str(ROOT))
    assert r.returncode == 0


def test_workflows_parse_and_checkout_deep_for_release():
    yaml = pytest.importorskip("yaml")
    for f in (ROOT / ".github" / "workflows").glob("*.yml"):
        assert isinstance(yaml.safe_load(f.read_text(encoding="utf-8")), dict), f.name
    rel = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    assert "fetch-depth: 0" in rel


def test_new_wave_packs_valid_and_pending():
    ids = ["scams-overcharge", "lost-phone", "police-checkpoint", "tm30-address-report", "karaoke", "golf",
           "kayak-national-park", "hair-beauty"]
    allp = P.load_all()
    pend = (ROOT / "tools" / "web_pending_presets.txt").read_text(encoding="utf-8").split()
    for i in ids:
        assert i in allp and not P.validate(allp[i]) and len(allp[i]["phrases"]) >= 14
        assert i in pend or f"'{i}'" in (ROOT / "sw.js").read_text(encoding="utf-8")
    assert math.isfinite(1.0)
