"""purge: ungültige Tage löschen nichts; gelöschte Texte bleiben nicht in der Datei lesbar."""
import argparse
import json
import time

import pytest

import history_store as hs

OLD = time.time() - 90 * 86400
MARK_EN = "Zebrafink-Geheimnis-4711"
MARK_TH = "ความลับนกฟินช์ม้าลาย"


@pytest.fixture
def st(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path / "home"))
    s = hs.Store()
    s.add("recent", "ใหม่", lang="en", session="s1")
    s.add(MARK_EN, MARK_TH, lang="en", session="s0", ts=OLD)
    yield s
    s.close()


@pytest.mark.parametrize("days", [0, -1, -0.5, "0", "-3", float("nan"), float("inf"), float("-inf"),
                                  None, "abc", True])
def test_purge_rejects_invalid_days(st, days):
    with pytest.raises(ValueError):
        st.purge(days)
    assert len(st.rows()) == 2


def test_purge_valid_days(st):
    assert st.purge(30) == 1
    assert st.purge("30") == 0
    assert [r["text"] for r in st.rows()] == ["recent"]


def test_secure_delete_on(st):
    assert st.db.execute("PRAGMA secure_delete").fetchone()[0] == 1


@pytest.mark.parametrize("how", ["purge", "clear"])
def test_deleted_text_not_in_file(st, how):
    getattr(st, how)(*((30,) if how == "purge" else ()))
    assert st.search(MARK_EN[:8]) == []
    path = st.path
    st.close()
    raw = open(path, "rb").read()
    for mark in (MARK_EN, MARK_TH):
        b = mark.encode("utf-8")
        assert b not in raw and b[:12] not in raw, mark   # auch keine Trigramm-Reste im FTS-Index
    st.db = __import__("sqlite3").connect(path)          # Fixture schließt erneut


def test_recorder_ignores_invalid_keep_days(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path / "home"))
    s = hs.Store()
    s.add("old", None, session="x", ts=OLD)
    s.close()
    for bad in (0, -1, "0", float("-inf")):
        r = hs.Recorder()
        r.enable(True, keep_days=bad)
        assert r.on and r.keep_days is None              # Verlauf bleibt an, nichts gelöscht
        assert len(r.store.rows()) == 1
        r.store.close()
    r = hs.Recorder()
    r.enable(True, keep_days=30)
    assert r.on and r.store.rows() == []
    r.store.close()


def _args(**kw):
    d = dict(history_export=None, history_search=None, history_purge=None, history_clear=False,
             history_session=None, out=None)
    d.update(kw)
    return argparse.Namespace(**d)


def test_cli_purge_invalid(st, capsys):
    assert hs.run_cli(_args(history_purge=-1.0)) == 2
    assert "error" in json.loads(capsys.readouterr().out)
    assert len(st.rows()) == 2
    assert hs.run_cli(_args(history_purge=30.0)) == 0
    assert json.loads(capsys.readouterr().out) == {"deleted": 1}


def test_cli_csv_export_has_bom(st, tmp_path):
    out = tmp_path / "h.csv"
    assert hs.run_cli(_args(history_export="csv", out=str(out))) == 0
    raw = out.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf") and "ใหม่".encode() in raw
    js = tmp_path / "h.json"
    assert hs.run_cli(_args(history_export="json", out=str(js))) == 0
    assert not js.read_bytes().startswith(b"\xef\xbb\xbf")
