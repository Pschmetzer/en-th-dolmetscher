"""Runde 25: optional verschlüsselter Verlauf (Feldverschlüsselung, eigene Datei, Passwort über Steuerfeld)."""
import json
import sqlite3
import types

import pytest

import dolmetscher as d
import history_store as hs

PW = "correct horse"


@pytest.fixture(autouse=True)
def _fast_kdf(monkeypatch, tmp_path):
    monkeypatch.setitem(hs._SCRYPT, "n", 2 ** 10)
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path / "home"))
    monkeypatch.delenv(hs.CLI_PASSWORD_ENV, raising=False)


def _store(tmp_path, pw=PW, name="e.sqlite"):
    return hs.Store(str(tmp_path / name), passphrase=pw)


def _fill(st):
    st.add("Where is the market?", "ตลาดอยู่ที่ไหน", lang="en", translit="talat yu thi nai", session="s1",
           uid="u1", ts=1000.0)
    st.add("ราคาเท่าไร", "How much?", lang="th", session="s1", uid="u2", ts=1010.0)
    st.add("Where is the market?", "ตลาดอยู่ที่ไหน", lang="en", session="s2", uid="u3", ts=86400 * 3 + 5.0)


def test_default_path_is_separate_file(tmp_path):
    assert hs.db_path(True).endswith("history-enc.sqlite") and hs.db_path().endswith("history.sqlite")


def test_plaintext_not_on_disk_and_roundtrip(tmp_path):
    st = _store(tmp_path)
    _fill(st)
    st.close()
    blob = b"".join(p.read_bytes() for p in tmp_path.glob("e.sqlite*"))
    for secret in ("market", "ราคา".encode().decode(), "talat", "How much"):
        assert secret.encode() not in blob
    st2 = _store(tmp_path)
    rows = st2.rows()
    assert [r["text"] for r in rows] == ["Where is the market?", "ราคาเท่าไร", "Where is the market?"]
    assert rows[0]["translation"] == "ตลาดอยู่ที่ไหน" and rows[0]["translit"] == "talat yu thi nai"
    assert st2.encrypted
    st2.close()


def test_wrong_password_and_missing_password_are_clean_errors(tmp_path):
    _store(tmp_path).close()
    with pytest.raises(hs.HistoryLocked):
        _store(tmp_path, "falsch")
    with pytest.raises(hs.HistoryLocked):
        hs.Store(str(tmp_path / "e.sqlite"))                 # ohne Passwort öffnen: nicht als Klartext lesen


def test_empty_or_non_string_password_rejected(tmp_path):
    for bad in ("", 5, b"x"):
        with pytest.raises(hs.HistoryLocked):
            hs.Store(str(tmp_path / "x.sqlite"), passphrase=bad)


def test_passphrase_on_plaintext_database_refused(tmp_path):
    st = hs.Store(str(tmp_path / "p.sqlite"))
    st.add("hello", session="s", ts=1.0)
    st.close()
    with pytest.raises(hs.HistoryLocked):
        hs.Store(str(tmp_path / "p.sqlite"), passphrase=PW)


def test_fields_have_fresh_nonce_and_prefix(tmp_path):
    st = _store(tmp_path)
    _fill(st)
    raw = [r[0] for r in st.db.execute("SELECT text FROM utt")]
    assert all(x.startswith("enc1:") for x in raw)
    assert raw[0] != raw[2]                                  # gleicher Text, anderes Nonce
    st.close()


def test_empty_and_none_fields_stay_plain(tmp_path):
    st = _store(tmp_path)
    st.add("x", translation=None, session="s", ts=1.0)
    st.add("y", translation="", session="s", ts=2.0)
    assert [r[0] for r in st.db.execute("SELECT translation FROM utt ORDER BY id")] == [None, ""]
    assert st.last_translation() is None
    st.close()


def test_tampered_or_swapped_field_returns_none_not_garbage(tmp_path):
    st = _store(tmp_path)
    _fill(st)
    t, tr = st.db.execute("SELECT text, translation FROM utt WHERE uid='u1'").fetchone()
    st.db.execute("UPDATE utt SET text = ?, translation = ? WHERE uid='u1'", (tr, t))   # Spalten vertauscht
    st.db.commit()
    row = st.rows()[0]
    assert row["text"] is None and row["translation"] is None
    st.close()


def test_search_works_without_fts_incl_thai_and_filters(tmp_path):
    st = _store(tmp_path)
    _fill(st)
    assert st.fts is False
    assert {r["uid"] for r in st.search("MARKET")} == {"u1", "u3"}
    assert [r["uid"] for r in st.search("ราคา")] == ["u2"]
    assert [r["uid"] for r in st.search("how much")] == ["u2"]
    assert [r["uid"] for r in st.search("market", session="s2")] == ["u3"]
    hit = st.search("ราคา", context=1)[0]
    assert [c["text"] for c in hit["context"]] == ["Where is the market?"]
    st.close()


def test_stats_decrypts_for_words_and_top_sentences(tmp_path):
    st = _store(tmp_path)
    _fill(st)
    s = st.stats()
    assert s["total"] == 3 and s["sessions"] == 2
    assert s["top_sentences"] == [{"text": "Where is the market?", "count": 2}]
    assert sum(v["words"] for v in s["per_day"].values()) == 4 + 1 + 4
    st.close()


def test_last_translation_and_export_are_plaintext(tmp_path):
    st = _store(tmp_path)
    _fill(st)
    assert st.last_translation() == {"lang": "en", "translation": "ตลาดอยู่ที่ไหน"}
    out = json.loads(hs.export(st.rows(), "json"))
    assert out[1]["text"] == "ราคาเท่าไร"
    st.close()


def test_duplicate_uid_same_content_not_added_twice(tmp_path):
    st = _store(tmp_path)
    a = st.add("hello", "hallo", session="s", uid="u9", ts=5.0)
    b = st.add("hello", "hallo", session="s", uid="u9", ts=5.0)
    c = st.add("hello", "hallo2", session="s", uid="u9", ts=5.0)
    assert a == b != c and st.count() == 2
    st.close()


def test_replaces_and_purge_work_encrypted(tmp_path):
    st = _store(tmp_path)
    _fill(st)
    st.add("neu", "new", session="s1", uid="u1b", replaces="u1", ts=1001.0)
    assert [r["text"] for r in st.rows("s1")] == ["neu", "ราคาเท่าไร"]
    assert st.purge_session("s2") == 1
    assert st.clear() == 2 and st.count() == 0
    st.close()


def test_import_json_roundtrip_and_dedup_encrypted(tmp_path):
    src = _store(tmp_path, name="a.sqlite")
    _fill(src)
    blob = hs.export(src.rows(), "json")
    dst = _store(tmp_path, name="b.sqlite")
    assert dst.import_json(blob) == (3, 0, 0)
    assert dst.import_json(blob) == (0, 3, 0)
    assert [r["text"] for r in dst.rows()][1] == "ราคาเท่าไร"
    assert dst.db.execute("SELECT text FROM utt LIMIT 1").fetchone()[0].startswith("enc1:")
    src.close()
    dst.close()


def test_iter_rows_decrypts_in_chunks(tmp_path):
    st = _store(tmp_path)
    for i in range(7):
        st.add(f"satz {i}", f"t{i}", session="s", ts=float(i))
    assert [r["text"] for r in st.iter_rows(chunk=3)] == [f"satz {i}" for i in range(7)]
    st.close()


def test_key_derived_once_not_per_row(tmp_path, monkeypatch):
    calls = []
    real = hs._derive_key
    monkeypatch.setattr(hs, "_derive_key", lambda *a, **k: calls.append(1) or real(*a, **k))
    st = _store(tmp_path)
    for i in range(20):
        st.add(f"t{i}", session="s", ts=float(i))
    st.rows()
    assert len(calls) == 1
    st.close()


def test_password_not_kept_on_store_object(tmp_path):
    st = _store(tmp_path)
    assert st._passphrase is None
    st.close()


def test_pbkdf2_fallback_records_kdf_and_reopens(tmp_path, monkeypatch):
    monkeypatch.delattr(hs.hashlib, "scrypt")
    monkeypatch.setitem(hs._SCRYPT, "n", 2 ** 10)
    monkeypatch.setattr(hs, "_PBKDF2_ITER", 1000)
    st = _store(tmp_path)
    st.add("hi", session="s", ts=1.0)
    assert st.db.execute("SELECT value FROM meta WHERE key='enc_kdf'").fetchone()[0] == str(hs._KDF_PBKDF2)
    st.close()
    assert _store(tmp_path).rows()[0]["text"] == "hi"


def test_damaged_meta_gives_locked_not_crash(tmp_path):
    _store(tmp_path).close()
    db = sqlite3.connect(str(tmp_path / "e.sqlite"))
    db.execute("UPDATE meta SET value = 'zz' WHERE key = 'enc_salt'")
    db.commit()
    db.close()
    with pytest.raises(hs.HistoryLocked):
        _store(tmp_path)


# ---- Recorder / Engine -------------------------------------------------------------------------------------

def test_recorder_enable_with_password_writes_encrypted_file(tmp_path):
    rec = hs.Recorder()
    assert rec.enable(True, passphrase=PW) is True
    rec.utt({"text": "guten tag", "out": "hello", "translated": True, "lang": "de"})
    rec.flush()
    assert rec.store.encrypted and rec.store.path.endswith("history-enc.sqlite")
    rec.store.close()
    blob = (tmp_path / "home" / "history-enc.sqlite").read_bytes()
    assert b"guten tag" not in blob


def test_recorder_password_switch_closes_plaintext_store(tmp_path):
    rec = hs.Recorder()
    assert rec.enable(True) and not rec.store.encrypted
    assert rec.enable(True, passphrase=PW) and rec.store.encrypted
    rec.store.close()


def test_recorder_wrong_password_reports_locked_and_stays_off(tmp_path):
    hs.Store(passphrase=PW).close()
    rec = hs.Recorder()
    assert rec.enable(True, passphrase="nope") is False
    assert rec.on is False and isinstance(rec.last_error, hs.HistoryLocked)


def test_recorder_without_password_keeps_encrypted_store(tmp_path):
    rec = hs.Recorder()
    rec.enable(True, passphrase=PW)
    st = rec.store
    rec.enable(True)
    assert rec.store is st and st.encrypted
    st.close()


def test_cli_with_env_password_reads_encrypted(tmp_path, monkeypatch, capsys):
    st = hs.Store(passphrase=PW)
    st.add("hallo welt", "hello world", lang="de", session="s", ts=1.0)
    st.close()
    monkeypatch.setenv(hs.CLI_PASSWORD_ENV, PW)
    a = types.SimpleNamespace(history_export="txt", history_session=None, out=None, history_search=None,
                              history_purge=None, history_clear=False, history_sessions=False)
    assert hs.run_cli(a) == 0
    assert "hello world" in capsys.readouterr().out
    monkeypatch.setenv(hs.CLI_PASSWORD_ENV, "falsch")
    assert hs.run_cli(a) == 2
    assert "falsches Passwort" in capsys.readouterr().out


def test_cli_password_without_encrypted_db_does_not_create_one(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv(hs.CLI_PASSWORD_ENV, PW)
    a = types.SimpleNamespace(history_export="txt", history_session=None, out=None, history_search=None,
                              history_purge=None, history_clear=False, history_sessions=False)
    assert hs.run_cli(a) == 2
    assert not (tmp_path / "home" / "history-enc.sqlite").exists()


@pytest.fixture
def _eng_env(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    monkeypatch.setitem(d.HIST_PASS, "pw", None)
    monkeypatch.setattr(hs, "RECORDER", hs.Recorder())
    return ev


def test_control_history_password_is_secret_and_known(_eng_env):
    assert "history_password" in d.CTRL_KEYS and "history_password" not in d.CTRL_LOG_KEYS
    assert "control:history_password" in d.capabilities()


def test_control_sets_clears_and_validates_password(_eng_env):
    eng = types.SimpleNamespace()
    d.apply_control(eng, {"history_password": "geheim"})
    assert d.HIST_PASS["pw"] == "geheim"
    d.apply_control(eng, {"history_password": ""})
    assert d.HIST_PASS["pw"] is None
    d.apply_control(eng, {"history_password": 12345})
    assert d.HIST_PASS["pw"] is None and ("control_invalid", {"key": "history_password", "reason": "value"}) in _eng_env
    d.apply_control(eng, {"history_password": "x" * 300})
    assert d.HIST_PASS["pw"] is None


def test_history_enable_uses_password_and_reports_wrong_password(_eng_env, tmp_path):
    hs.Store(passphrase=PW).close()
    d.HIST_PASS["pw"] = "pw-xyz-9"
    d.history_enable(True)
    errs = [kw for e, kw in _eng_env if e == "error"]
    assert errs and errs[-1]["code"] == "history_failed" and "Passwort" in errs[-1]["msg"]
    assert "pw-xyz-9" not in json.dumps(errs)
    d.HIST_PASS["pw"] = PW
    d.history_enable(True)
    assert hs.RECORDER.on and hs.RECORDER.store.encrypted
    hs.RECORDER.store.close()


def test_password_never_in_logged_control_line(_eng_env):
    """Die Steuerzeile loggt nur Felder aus CTRL_LOG_KEYS (und Textfelder bei --log-text) im Klartext."""
    assert "history_password" not in d.CTRL_LOG_KEYS
    assert "history_password" not in getattr(d, "TEXT_CTRL_KEYS", ())


# ---- Nachbesserung nach Review: Sprechername, Startpasswort, Quelle + Mikrofon in einer Zeile --------------------

def test_speaker_names_are_encrypted_not_readable_in_file(tmp_path):
    st = _store(tmp_path)
    st.add("hallo", "hello", session="s", ts=1.0, speaker="Somchai Prasert", role="other")
    assert st.rows()[0]["speaker"] == "Somchai Prasert"
    assert st.db.execute("SELECT speaker FROM utt").fetchone()[0].startswith("enc1:")
    assert st.db.execute("SELECT role FROM utt").fetchone()[0] == "other"        # Rolle bleibt lesbar (dokumentiert)
    st.close()
    blob = b"".join(p.read_bytes() for p in tmp_path.glob("e.sqlite*"))
    assert b"Somchai" not in blob


def test_speaker_roundtrip_through_encrypted_import_and_export(tmp_path):
    src = _store(tmp_path, name="a.sqlite")
    src.add("hallo", session="s", ts=1.0, speaker="Anan")
    dst = _store(tmp_path, name="b.sqlite")
    assert dst.import_json(hs.export(src.rows(), "json")) == (1, 0, 0)
    assert dst.rows()[0]["speaker"] == "Anan"
    assert dst.db.execute("SELECT speaker FROM utt").fetchone()[0].startswith("enc1:")
    src.close()
    dst.close()


def test_plain_store_still_stores_speaker_plain(tmp_path):
    st = hs.Store(str(tmp_path / "p.sqlite"))
    st.add("hallo", session="s", ts=1.0, speaker="Anan")
    assert st.db.execute("SELECT speaker FROM utt").fetchone()[0] == "Anan"
    st.close()


def test_history_password_from_env_moves_secret_out_of_environment(monkeypatch):
    monkeypatch.setitem(d.HIST_PASS, "pw", None)
    monkeypatch.setenv(hs.CLI_PASSWORD_ENV, "start-pw")
    assert d.history_password_from_env() is True
    assert d.HIST_PASS["pw"] == "start-pw"
    assert hs.CLI_PASSWORD_ENV not in d.os.environ
    assert d.history_password_from_env() is False


def test_password_env_is_never_passed_to_child_processes():
    assert hs.CLI_PASSWORD_ENV in d._SECRET_ENV
    assert hs.CLI_PASSWORD_ENV not in d._child_env({hs.CLI_PASSWORD_ENV: "x", "PATH": "/bin"})


def test_start_history_flag_reads_env_password_before_first_write():
    src = open(d.__file__, encoding="utf-8").read()
    i = src.index("history_password_from_env()                  # Runde 25")
    assert "history_enable(True, a.history_days)" in src[i:i + 200]


def test_source_and_mic_in_one_control_line_keep_the_device_change(monkeypatch):
    calls = []

    class FakeMic:
        on, mic, stops = True, "0", 0

        def switch(self, mv):
            calls.append((mv, d.SOURCE["kind"]))

        def start(self):
            pass

        def stop(self):
            pass
    monkeypatch.setattr(d, "MIC", FakeMic())
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setitem(d.SOURCE, "kind", "mic")
    job = d.apply_control(types.SimpleNamespace(), {"mic": "USB Mic", "source": "system"})
    job()
    assert calls == [("USB Mic", "system")]
