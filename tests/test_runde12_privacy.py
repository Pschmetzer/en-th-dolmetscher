"""Runde 12: Datenschutz der lokalen Daten – Logs, Fehlermeldungen, Cache, Stimmprofile, Verlauf."""
import json
import os
import re
import stat

import pytest

import dolmetscher as dm
import history_store
import profiles


@pytest.fixture
def logfile(tmp_path, monkeypatch):
    monkeypatch.setattr(dm, "LOGFILE", str(tmp_path / "logs" / "engine.log"))
    monkeypatch.setattr(dm, "_LOGGER", None)
    lg = dm._make_logger()
    monkeypatch.setattr(dm, "_logger", lambda: lg)      # conftest ersetzt den Logger durch einen Null-Logger
    yield tmp_path / "logs" / "engine.log"
    for h in list(lg.handlers):
        h.close()
        lg.removeHandler(h)
    monkeypatch.setattr(dm, "_LOGGER", None)


def test_log_traegt_keinen_benutzernamen(logfile):
    home = os.path.expanduser("~")
    dm.log({"offline_mt": "helfer fehlt", "path": "/Users/alice/Library/x/translate-helper"})
    dm.log({"datei": home + "/Library/Application Support/Dolmetscher/anthropic_key"})
    text = logfile.read_text(encoding="utf-8")
    assert "alice" not in text
    assert home not in text or home == "/"


def test_fehlerereignis_maskiert_pfade():
    line = dm._json_line("error", {"code": "profile_delete_failed",
                                   "msg": "Stimmdaten konnten nicht gelöscht werden: [Errno 13] "
                                          "'/Users/alice/Library/Application Support/Dolmetscher/profiles/Anna.json'"})
    assert "alice" not in line
    assert json.loads(line)["code"] == "profile_delete_failed"


def test_log_fehler_ohne_repr():
    """repr(Ausnahme) kann Gesprächsfragmente oder Pfade zitieren: ins Log gehört nur _errtxt()."""
    src = open(dm.__file__, encoding="utf-8").read()
    assert not re.search(r"repr\(e\)", src)


def test_errtxt_laesst_zitierten_text_draussen():
    assert "Geheim" not in dm._errtxt(KeyError("Geheim Gespräch"))
    assert "Geheim" not in dm._errtxt(ValueError("Geheim Gespräch"))


def test_cache_wird_nach_ausschalten_nicht_neu_geschrieben(tmp_path, monkeypatch):
    f = tmp_path / "translation_cache.json"
    monkeypatch.setattr(dm, "CACHE_FILE", str(f))
    monkeypatch.setitem(dm._CACHE_DISK, "on", True)
    dm._cache_put(("a", "en", "th", "x", "y"), "GEHEIM")
    dm._cache_save(force=True)
    assert f.exists() and stat.S_IMODE(f.stat().st_mode) == 0o600
    dm.cache_persist(False)
    assert not f.exists()
    dm._cache_save(force=True)                     # ein später Schreibvorgang darf die Datei nicht neu anlegen
    assert not f.exists()
    dm._CACHE.clear()


def test_cache_ist_begrenzt(tmp_path, monkeypatch):
    f = tmp_path / "translation_cache.json"
    monkeypatch.setattr(dm, "CACHE_FILE", str(f))
    monkeypatch.setitem(dm._CACHE_DISK, "on", True)
    for i in range(dm._CACHE_MAX + 50):
        dm._cache_put(("a", "en", "th", str(i), "y"), "v")
    dm._cache_save(force=True)
    assert len(json.loads(f.read_text(encoding="utf-8"))) <= dm._CACHE_MAX
    dm.cache_persist(False)
    dm._CACHE.clear()


def test_profil_loeschen_entfernt_tmp_reste(tmp_path, monkeypatch):
    d = tmp_path / "profiles"
    monkeypatch.setattr(profiles, "PROFILE_DIR", str(d))
    profiles.save_profile({"name": "Anna", "lang": "en", "embedding": [1.0, 0.0]})
    rest = d / "Anna.json.123.456.tmp"              # Rest eines abgebrochenen Schreibvorgangs mit Stimmabdruck
    rest.write_text('{"embedding": [1.0, 0.0]}')
    assert profiles.delete_profile("Anna")
    assert not rest.exists()
    assert stat.S_IMODE(d.stat().st_mode) == 0o700


def test_verlauf_loeschen_laesst_nichts_in_wal_shm(tmp_path):
    p = tmp_path / "h" / "history.sqlite"
    s = history_store.Store(str(p))
    s.add("GEHEIMWORT", translation="GEHEIMUEBERSETZUNG", lang="en", provider="g")
    s.db.commit()
    for suffix in ("", "-wal", "-shm"):
        f = str(p) + suffix
        if os.path.exists(f):
            assert stat.S_IMODE(os.stat(f).st_mode) == 0o600, suffix
    s.clear()
    for suffix in ("", "-wal", "-shm"):
        f = str(p) + suffix
        if os.path.exists(f):
            assert b"GEHEIM" not in open(f, "rb").read(), suffix
    s.close()
