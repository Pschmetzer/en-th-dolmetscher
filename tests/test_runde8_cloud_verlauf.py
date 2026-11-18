"""Runde 8 (Cloud): Gesprächsverlauf (history_store.py) – Datenschutz, Export, Suche, Migration, Aufzeichnung."""
import csv
import io
import json
import os
import sqlite3
import stat
import time
import types

import pytest

import history_store as hs


@pytest.fixture
def store(tmp_path):
    s = hs.Store(str(tmp_path / "h" / "history.sqlite"))
    yield s
    try:
        s.close()
    except sqlite3.Error:
        pass


def _fill(s):
    s.add("hello world", translation="สวัสดีชาวโลก", lang="en", session="a", ts=1000.0, role="me", speaker="Anna")
    s.add("hello again", lang="en", session="a", ts=1001.0)
    s.add("ราคาเท่าไหร่", translation="how much", lang="th", translit="rakha thaorai", session="b", ts=2000.0)
    s.add("100% sure_thing", lang="en", session="b", ts=2001.0)
    return s


# ---- Dateirechte (Datenschutz) ----------------------------------------------------------------------------------

def test_new_store_is_private(tmp_path):
    p = tmp_path / "neu" / "history.sqlite"
    s = hs.Store(str(p))
    s.close()
    assert stat.S_IMODE(os.stat(p).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(p.parent).st_mode) == 0o700


def test_existing_wide_file_is_tightened_but_existing_dir_untouched(tmp_path):
    d = tmp_path / "vorhanden"
    d.mkdir()
    os.chmod(d, 0o755)
    f = d / "history.sqlite"
    f.write_bytes(b"")
    os.chmod(f, 0o644)
    hs.Store(str(f)).close()
    assert stat.S_IMODE(os.stat(f).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(d).st_mode) == 0o755        # fremden Ordner nie ändern


def test_db_path_follows_home_env(monkeypatch, tmp_path):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    assert hs.db_path() == str(tmp_path / "history.sqlite")


# ---- Löschen ohne Reste -----------------------------------------------------------------------------------------

def test_clear_removes_text_from_the_file_bytes(tmp_path):
    p = tmp_path / "h.sqlite"
    s = hs.Store(str(p))
    secret = "GEHEIMERSATZXYZ123"
    s.add(secret, translation="ÜBERSETZTGEHEIM987", lang="en", session="a")
    assert s.clear() == 1
    s.close()
    blob = b"".join(open(q, "rb").read() for q in tmp_path.iterdir())
    assert secret.encode() not in blob and "ÜBERSETZTGEHEIM987".encode() not in blob


def test_clear_empties_search_index_too(store):
    _fill(store)
    store.clear()
    assert store.search("hello") == [] and store.rows() == [] and store.sessions() == []


def test_purge_only_deletes_old_rows(store):
    now = time.time()
    store.add("alt", ts=now - 40 * 86400)
    store.add("neu", ts=now - 1 * 86400)
    assert store.purge(30) == 1
    assert [r["text"] for r in store.rows()] == ["neu"]
    assert store.search("alt") == []


def test_purge_returns_zero_when_nothing_old(store):
    store.add("neu")
    assert store.purge(30) == 0 and len(store.rows()) == 1


@pytest.mark.parametrize("bad", [0, -1, float("inf"), float("nan"), "x", None, True, [3], {}])
def test_purge_rejects_dangerous_days_and_deletes_nothing(store, bad):
    store.add("bleibt")
    with pytest.raises(ValueError):
        store.purge(bad)
    assert len(store.rows()) == 1


@pytest.mark.parametrize("v,want", [(30, 30.0), ("7", 7.0), (0.5, 0.5), (0, None), (-3, None), (True, None),
                                    (float("nan"), None), (float("inf"), None), ("abc", None), (None, None),
                                    ([], None)])
def test_valid_days(v, want):
    assert hs.valid_days(v) == want


# ---- Suche ----------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("q", ['"', "'", "\\", "NEAR(", "a OR b", "AND", "hel*", "%%%", "  ", "", None, "\x00"])
def test_search_never_raises_on_odd_queries(store, q):
    _fill(store)
    assert isinstance(store.search(q), list)


def test_search_thai_substring(store):
    _fill(store)
    assert [r["text"] for r in store.search("สวัส")] == ["hello world"]
    assert [r["text"] for r in store.search("เท่าไหร่")] == ["ราคาเท่าไหร่"]


def test_search_percent_and_underscore_are_literal(store):
    _fill(store)
    assert [r["text"] for r in store.search("100%")] == ["100% sure_thing"]
    assert [r["text"] for r in store.search("e_t")] == ["100% sure_thing"]
    assert store.search("o_l") == []          # "_" ist kein Platzhalter


def test_search_short_query_uses_like(store):
    _fill(store)
    assert {r["text"] for r in store.search("he")} == {"hello world", "hello again"}


def test_search_finds_translation_column(store):
    _fill(store)
    assert [r["text"] for r in store.search("how much")] == ["ราคาเท่าไหร่"]


def test_search_orders_newest_first_and_limits(store):
    _fill(store)
    assert [r["text"] for r in store.search("hello")] == ["hello again", "hello world"]
    assert len(store.search("hello", limit=1)) == 1


def test_search_filters(store):
    _fill(store)
    assert store.search("hello", lang="th") == []
    assert [r["text"] for r in store.search("hello", session="a", since=1000.5)] == ["hello again"]
    assert store.search("hello", session="b") == []


def test_search_context_stays_in_session_and_is_capped(store):
    for i in range(30):
        store.add(f"zeile {i:02d}", session="a", ts=float(i))
    store.add("zeile 99 fremd", session="b", ts=40.0)
    hit = store.search("zeile 15", context=999)[0]
    assert len(hit["context"]) == 20                       # höchstens 10 davor + 10 danach
    assert all(c["text"].startswith("zeile") and "fremd" not in c["text"] for c in hit["context"])


@pytest.mark.parametrize("ctx", [-5, None, 0])
def test_search_context_zero_negative_or_none_adds_no_context(store, ctx):
    _fill(store)
    assert all("context" not in r for r in store.search("hello", context=ctx))


# ---- Hinzufügen / Ersetzen -------------------------------------------------------------------------------------

def test_replace_deletes_old_row_and_index_entry(store):
    store.add("falsch erkannt", uid="u1", session="a")
    store.add("richtig erkannt", uid="u2", session="a", replaces="u1")
    assert [r["text"] for r in store.rows()] == ["richtig erkannt"]
    assert store.search("falsch") == []


def test_replace_unknown_uid_still_inserts(store):
    store.add("neu", uid="u9", replaces="gibt-es-nicht")
    assert len(store.rows()) == 1


def test_last_translation_skips_empty(store):
    store.add("a", translation="b", lang="en", ts=1.0)
    store.add("c", translation="", lang="en", ts=2.0)
    store.add("d", translation=None, lang="en", ts=3.0)
    assert store.last_translation() == {"lang": "en", "translation": "b"}


def test_last_translation_empty_store(store):
    assert store.last_translation() is None


def test_sessions_newest_first_with_counts(store):
    _fill(store)
    assert store.sessions() == [("b", 2000.0, 2), ("a", 1000.0, 2)]


# ---- Schema-Migration ----------------------------------------------------------------------------------------------

def test_v1_database_is_migrated_and_keeps_rows(tmp_path):
    p = str(tmp_path / "alt.sqlite")
    con = sqlite3.connect(p)
    con.execute("CREATE TABLE utt (id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT, ts REAL NOT NULL, "
                "session TEXT NOT NULL, lang TEXT, text TEXT, translation TEXT, translit TEXT, conf REAL, "
                "provider TEXT)")
    con.execute("INSERT INTO utt (uid, ts, session, lang, text) VALUES ('x', 5.0, 's', 'en', 'alter Satz')")
    con.commit()
    con.close()
    s = hs.Store(p)
    assert s.db.execute("PRAGMA user_version").fetchone()[0] == hs.SCHEMA_VERSION
    row = s.rows()[0]
    assert row["text"] == "alter Satz" and row["t_begin"] is None and row["role"] is None
    s.add("neu", role="me")
    s.close()


def test_database_from_newer_version_is_rejected_untouched(tmp_path):
    p = str(tmp_path / "neu.sqlite")
    hs.Store(p).close()
    con = sqlite3.connect(p)
    con.execute(f"PRAGMA user_version = {hs.SCHEMA_VERSION + 1}")
    con.commit()
    con.close()
    with pytest.raises(sqlite3.DatabaseError):
        hs.Store(p)
    con = sqlite3.connect(p)
    assert con.execute("PRAGMA user_version").fetchone()[0] == hs.SCHEMA_VERSION + 1
    con.close()


# ---- Export --------------------------------------------------------------------------------------------------------

def test_export_unknown_format_raises_and_is_case_insensitive(store):
    _fill(store)
    with pytest.raises(ValueError):
        hs.export(store.rows(), "pdf")
    assert hs.export(store.rows(), "JSON") == hs.export(store.rows(), "json")


def test_export_empty_rows_all_formats():
    assert json.loads(hs.export([], "json")) == []
    assert hs.export([], "csv").startswith("time,session")
    assert hs.export([], "vtt") == "WEBVTT\n"
    assert hs.export([], "srt") == ""
    assert hs.export([], "md").startswith("# Gesprächsverlauf")
    assert hs.export([], "anki").count("\n") == 6 - 1


def test_csv_formula_injection_is_defused_in_every_cell(store):
    store.add("=HYPERLINK(\"http://x\")", translation="+1+1", translit="-2", lang="@sum", provider="\tcmd",
              session="=s", speaker="@evil", role="me")
    rows = list(csv.reader(io.StringIO(hs.export(store.rows(), "csv"))))
    for cell in rows[1]:
        assert cell[:1] not in ("=", "+", "-", "@", "\t", "\r")


def test_csv_roundtrip_keeps_thai_commas_quotes_and_newlines(store):
    store.add('sagt "hallo", dann\nZeile 2', translation="สวัสดี, โลก", lang="en", session="a", ts=1.0)
    row = list(csv.reader(io.StringIO(hs.export(store.rows(), "csv"))))[1]
    assert row[3] == 'sagt "hallo", dann\nZeile 2' and row[4] == "สวัสดี, โลก"


def test_csv_speaker_columns_only_when_known(store):
    store.add("a", ts=1.0)
    assert "role" not in hs.export(store.rows(), "csv").splitlines()[0]
    store.add("b", ts=2.0, role="other", speaker="Bob")
    head = hs.export(store.rows(), "csv").splitlines()[0]
    assert head.endswith("role,speaker")


def test_json_export_has_no_internal_ids_and_includes_speaker_only_if_set(store):
    _fill(store)
    rows = json.loads(hs.export(store.rows(), "json"))
    assert all("id" not in r and "uid" not in r for r in rows)
    assert rows[0]["speaker"] == "Anna" and "speaker" not in rows[1]
    assert rows[0]["time"].endswith("Z")


def test_anki_skips_untranslated_and_collapses_whitespace_and_tabs(store):
    store.add("a\tb\n c", translation="x\ty", lang="en", session="s 1", ts=1.0)
    store.add("nur Original", lang="en", ts=2.0)
    store.add("gleich", translation="gleich", lang="en", ts=3.0)
    lines = hs.export(store.rows(), "anki").splitlines()
    cards = [ln for ln in lines if not ln.startswith("#")]
    assert len(cards) == 1
    cols = cards[0].split("\t")
    assert len(cols) == 5 and cols[1] == "a b c" and cols[2] == "x y"
    assert "\t" not in cols[4].replace(" ", "")


def test_anki_guid_is_stable_across_exports(store):
    _fill(store)
    assert hs.export(store.rows(), "anki") == hs.export(store.rows(), "anki")


def test_srt_has_numbered_cues_with_comma_and_vtt_with_dot(store):
    _fill(store)
    srt, vtt = hs.export(store.rows(), "srt"), hs.export(store.rows(), "vtt")
    assert srt.startswith("1\n00:00:00,000 --> ") and "2\n" in srt
    assert vtt.startswith("WEBVTT\n") and "00:00:00.000 --> " in vtt


def test_subtitle_end_never_before_start_and_flat_text(store):
    for i in range(5):
        store.add(f"satz {i}\n\nmit Leerzeile", translation=f"ü {i}", ts=100.0 + i * 0.1, session="a")
    cues = hs._cues(store.rows())
    assert all(e > s for s, e, _ in cues)
    assert all("\n\n" not in body for _, _, body in cues)


def test_clock_formatting_and_negative_clamp():
    assert hs._clock(3661.5, ",") == "01:01:01,500"
    assert hs._clock(-5, ".") == "00:00:00.000"


def test_start_prefers_t_begin_only_when_sane():
    assert hs._start({"ts": 10.0, "t_begin": 8.0}) == 8.0
    assert hs._start({"ts": 10.0, "t_begin": 12.0}) == 10.0          # Beginn nach dem Ende: unmöglich
    assert hs._start({"ts": 10.0, "t_begin": float("nan")}) == 10.0
    assert hs._start({"ts": 10.0, "t_begin": "8"}) == 10.0
    assert hs._start({"ts": 10.0}) == 10.0


def test_markdown_names_roles_and_speaker(store):
    store.add("ich", role="me", lang="en", ts=1.0, session="a")
    store.add("sie", role="other", lang="th", ts=2.0, session="a")
    store.add("Chef", role="me", speaker="Anna", lang="en", ts=3.0, session="a")
    md = hs.export(store.rows(), "md")
    assert "[EN · ich]" in md and "[TH · Partner]" in md and "[EN · Anna]" in md


def test_iso_is_utc_millis():
    assert hs._iso(0) == "1970-01-01T00:00:00.000Z"


# ---- t_begin / Recorder --------------------------------------------------------------------------------------------

@pytest.mark.parametrize("kw,fm,want", [
    ({"ready_s": 1.0, "dur": 2.0}, False, 97.0),
    ({"dur": 2.0}, True, 98.0),
    ({"ready_s": 1.0}, False, None),
    ({"ready_s": -1.0, "dur": 2.0}, False, None),
    ({"ready_s": True, "dur": 2.0}, False, None),
    ({"ready_s": float("nan"), "dur": 2.0}, False, None),
    ({"ready_s": "1", "dur": 2.0}, False, None),
])
def test_t_begin(kw, fm, want):
    assert hs._t_begin(kw, now=100.0, file_mode=fm) == want


@pytest.fixture
def rec(store):
    r = hs.Recorder()
    r.store, r.on = store, True
    return r


def test_recorder_off_writes_nothing(store):
    r = hs.Recorder()
    r.store = store
    r.utt({"text": "geheim"})
    assert store.rows() == []


def test_recorder_ignores_empty_text(rec, store):
    rec.utt({"text": ""})
    rec.utt({})
    assert store.rows() == []


def test_recorder_translated_flag_controls_translation(rec, store):
    rec.utt({"text": "a", "out": "b", "translated": True, "lang": "en"})
    rec.utt({"text": "c", "out": "d", "translated": False, "lang": "en"})
    assert [r["translation"] for r in store.rows()] == ["b", None]


def test_recorder_confidence_from_logprob(rec, store):
    rec.utt({"text": "a", "lp": -0.5})
    rec.utt({"text": "b", "lp": 0.0})
    rec.utt({"text": "c"})
    assert store.rows()[0]["conf"] == pytest.approx(0.607, abs=1e-3)
    assert store.rows()[1]["conf"] is None and store.rows()[2]["conf"] is None


def test_recorder_role_must_be_me_or_other(rec, store):
    rec.utt({"text": "a", "role": "admin"})
    rec.utt({"text": "b", "role": "me"})
    assert [r["role"] for r in store.rows()] == [None, "me"]


def test_recorder_speaker_privacy_switch(rec, store):
    rec.utt({"text": "a", "speaker": "Anna"})
    rec.store_speakers = False
    rec.utt({"text": "b", "speaker": "Anna"})
    rec.store_speakers = True
    rec.utt({"text": "c", "speaker": 5})
    assert [r["speaker"] for r in store.rows()] == ["Anna", None, None]


def test_recorder_translit_prefers_source_latin(rec, store):
    rec.utt({"text": "ก", "text_latin": "ko", "out_latin": "x"})
    rec.utt({"text": "ข", "out_latin": "kho"})
    assert [r["translit"] for r in store.rows()] == ["ko", "kho"]


def test_recorder_new_session_after_long_gap(rec, store):
    rec._write({"text": "a"}, 1_000_000.0)
    first = rec.session
    rec._write({"text": "b"}, 1_000_000.0 + 60)
    assert rec.session == first
    rec._write({"text": "c"}, 1_000_000.0 + 60 + rec.SESSION_GAP_S + 1)
    assert rec.session != first


def test_recorder_fixed_session_for_subtitles(rec):
    rec.fixed_session = True
    rec._write({"text": "a"}, 1.0)
    s = rec.session
    rec._write({"text": "b"}, 1.0 + 10 * rec.SESSION_GAP_S)
    assert rec.session == s


def test_recorder_database_error_turns_history_off_and_reports(rec, store):
    called = []
    rec.on_error = lambda: called.append(1)
    store.db.close()
    rec.utt({"text": "a"})
    assert rec.on is False and called == [1]


def test_recorder_failing_on_error_callback_is_swallowed(rec, store):
    rec.on_error = lambda: 1 / 0
    store.db.close()
    rec.utt({"text": "a"})
    assert rec.on is False


def test_recorder_locked_database_is_tolerated_twice(rec, store, monkeypatch):
    def locked(*a, **k):
        raise sqlite3.OperationalError("database is locked")
    monkeypatch.setattr(store, "add", locked)
    rec.utt({"text": "a"})
    rec.utt({"text": "b"})
    assert rec.on is True and rec.fails == 2
    rec.utt({"text": "c"})
    assert rec.on is False


def test_recorder_enable_with_invalid_days_keeps_history_on_and_deletes_nothing(monkeypatch, tmp_path):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    r = hs.Recorder()
    assert r.enable(True, keep_days=0) is True
    r.store.add("bleibt", ts=1.0)
    assert r.enable(True, keep_days=-1) is True and r.keep_days is None
    assert len(r.store.rows()) == 1
    r.store.close()


def test_recorder_enable_false_when_database_unusable(monkeypatch, tmp_path):
    f = tmp_path / "datei"
    f.write_text("x")
    monkeypatch.setenv("DOLMETSCHER_HOME", str(f / "unterordner"))    # Ordner unter einer Datei: nicht anlegbar
    r = hs.Recorder()
    assert r.enable(True) is False and r.on is False


def test_recorder_async_mode_flushes(rec, store):
    rec.async_mode = True
    for i in range(20):
        rec.utt({"text": f"satz {i}"})
    rec.flush()
    assert len(store.rows()) == 20


def test_recorder_file_mode_uses_file_position(rec, store):
    rec.file_pos, rec.file_base = 12.5, 1000.0
    rec.utt({"text": "a", "dur": 2.0})
    r = store.rows()[0]
    assert r["ts"] == 1012.5 and r["t_begin"] == 1010.5


# ---- CLI -----------------------------------------------------------------------------------------------------------

def _args(**kw):
    base = dict(history_export=None, history_search=None, history_purge=None, history_clear=False,
                history_sessions=False, history_session=None, history_context=0, history_lang=None, out=None)
    base.update(kw)
    return types.SimpleNamespace(**base)


def test_wants_cli():
    assert not hs.wants_cli(_args())
    assert hs.wants_cli(_args(history_clear=True))
    assert hs.wants_cli(_args(history_search=""))
    assert hs.wants_cli(_args(history_sessions=True))


def test_cli_purge_invalid_days_reports_error_code_2(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    assert hs.run_cli(_args(history_purge=0)) == 2
    assert "error" in json.loads(capsys.readouterr().out)


def test_cli_export_to_file_is_private_and_csv_has_bom(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    s = hs.Store()
    s.add("สวัสดี", translation="hi", lang="th", ts=1.0, session="a")
    s.close()
    out = tmp_path / "ex.csv"
    out.write_text("alt")
    os.chmod(out, 0o644)
    assert hs.run_cli(_args(history_export="csv", out=str(out))) == 0
    assert stat.S_IMODE(os.stat(out).st_mode) == 0o600
    assert out.read_bytes().startswith(b"\xef\xbb\xbf")
    assert json.loads(capsys.readouterr().out)["exported"] is True


def test_cli_search_prints_json_without_internal_fields(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    s = hs.Store()
    s.add("hello", lang="en", ts=1.0, session="a", speaker="Anna")
    s.close()
    assert hs.run_cli(_args(history_search="hello")) == 0
    hits = json.loads(capsys.readouterr().out)
    assert set(hits[0]) == {"time", "session", "lang", "text", "translation"}


def test_cli_clear_and_sessions(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    s = hs.Store()
    s.add("a", ts=1.0, session="x")
    s.close()
    hs.run_cli(_args(history_sessions=True))
    assert json.loads(capsys.readouterr().out) == [{"id": "x", "start": hs._iso(1.0), "count": 1}]
    hs.run_cli(_args(history_clear=True))
    assert json.loads(capsys.readouterr().out) == {"deleted": 1}


def test_cli_srt_export_takes_newest_session_only(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    s = hs.Store()
    s.add("alte Sitzung", ts=100.0, session="old")
    s.add("neue Sitzung", ts=900.0, session="new")
    s.close()
    hs.run_cli(_args(history_export="srt"))
    out = capsys.readouterr().out
    assert "neue Sitzung" in out and "alte Sitzung" not in out
