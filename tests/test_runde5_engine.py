"""Runde 5 (Engine): Offline-Übersetzer im Bundle, Preset-Felder, Privatmodus, MyMemory-Bewertung, Log-Rotation,
CPU-Threads, Audio-Ablauf, VAD-Selbsttest, Verlaufs-Schema und Tabellentests (Nr. 58, 199, 208)."""
import json
import os
import stat
import time
import types
import urllib.error

import numpy as np
import pytest

import dolmetscher as d
import history_store as hs
import hwprofile
import presets as P
import profiles


def _events(capsys):
    return [json.loads(x) for x in capsys.readouterr().out.splitlines() if x.startswith("{")]


# ---- translate-helper im App-Bundle (Contents/Helpers) -------------------------------------------------------

def _exe(path):
    path.write_text("#!/bin/sh\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def test_offline_mt_findet_helfer_im_bundle(tmp_path, monkeypatch):
    res = tmp_path / "Contents" / "Resources"
    helpers = tmp_path / "Contents" / "Helpers"
    res.mkdir(parents=True)
    helpers.mkdir()
    helper = _exe(helpers / "translate-helper")
    monkeypatch.setattr(d, "__file__", str(res / "dolmetscher.py"))
    monkeypatch.delenv("DOLMETSCHER_TRANSLATE_HELPER", raising=False)
    mt = d.OfflineMT()
    assert mt.bundled() == str(helper)
    assert mt.configure(None, on=True) and mt.path == str(helper)


def test_offline_mt_neben_engine_hat_vorrang(tmp_path, monkeypatch):
    (tmp_path / "Helpers").mkdir()
    _exe(tmp_path / "Helpers" / "translate-helper")
    res = tmp_path / "Resources"
    res.mkdir()
    near = _exe(res / "translate-helper")
    monkeypatch.setattr(d, "__file__", str(res / "dolmetscher.py"))
    assert d.OfflineMT.bundled() == str(near)


def test_offline_mt_ohne_helfer_aus(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "__file__", str(tmp_path / "dolmetscher.py"))
    monkeypatch.delenv("DOLMETSCHER_TRANSLATE_HELPER", raising=False)
    assert d.OfflineMT.bundled() is None
    assert d.OfflineMT().configure(None, on=True) is False


# ---- Presets: note/critical an die App ----------------------------------------------------------------------

def test_app_fields_liefert_note_und_critical():
    p = {"id": "x", "names": {"de": "X", "en": "X", "th": "X"}, "style": "polite",
         "note": {"de": "Hinweis", "en": "Note"},
         "phrases": [{"en": "Help!", "th": "ช่วยด้วย", "critical": True}, {"en": "Hi", "th": "สวัสดี"}]}
    f = P.app_fields(p)
    assert f["note"] == {"de": "Hinweis", "en": "Note"}
    assert f["phrases"] == [{"en": "Help!", "th": "ช่วยด้วย", "critical": True},
                            {"en": "Hi", "th": "สวัสดี", "critical": False}]
    assert P.app_fields(None) == {"note": None, "phrases": []}


def test_mitgelieferte_presets_haben_note_und_critical():
    allp = P.load_all()
    assert any(p.get("note") for p in allp.values())
    assert any(ph.get("critical") for p in allp.values() for ph in p["phrases"])


def test_preset_event_traegt_note_und_phrases(capsys, monkeypatch, tmp_path):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    monkeypatch.setattr(d, "JSON", True)
    monkeypatch.setattr(d, "PRESET", P.PresetState())
    monkeypatch.setattr(d, "GLOSSARY", [])
    eng = types.SimpleNamespace(polite="krub", voices={"en": None, "th": None})
    pid = next(k for k, p in P.load_all().items() if p.get("note") and any(x.get("critical") for x in p["phrases"]))
    d.set_preset(eng, pid)
    ev = [e for e in _events(capsys) if e.get("event") == "preset"][-1]
    assert ev["id"] == pid and ev["note"]["en"] and ev["note"]["de"]
    assert any(ph["critical"] for ph in ev["phrases"])


def test_ungueltiges_nutzer_preset_meldet_einmal(capsys, monkeypatch, tmp_path):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    monkeypatch.setattr(d, "JSON", True)
    monkeypatch.setattr(d, "PRESET", P.PresetState())
    monkeypatch.setattr(d, "GLOSSARY", [])
    monkeypatch.setitem(d._PRESET_REPORTED, "errors", None)
    (tmp_path / "presets").mkdir()
    (tmp_path / "presets" / "kaputt.json").write_text("{nope", encoding="utf-8")
    eng = types.SimpleNamespace(polite="krub", voices={"en": None, "th": None})
    d.set_preset(eng, "none")
    d.set_preset(eng, "none")
    errs = [e for e in _events(capsys) if e.get("event") == "error"]
    assert [e["code"] for e in errs] == ["preset_invalid"]
    assert errs[0]["files"] == ["kaputt.json"]


def test_nutzer_preset_ersetzt_mitgeliefertes_wird_gemerkt(monkeypatch, tmp_path):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    (tmp_path / "presets").mkdir()
    own = {"id": "hotel", "names": {"de": "Mein Hotel", "en": "My hotel", "th": "โรงแรม"}, "style": "neutral"}
    (tmp_path / "presets" / "hotel.json").write_text(json.dumps(own), encoding="utf-8")
    assert P.load_all()["hotel"]["names"]["en"] == "My hotel"
    assert P.overridden == ["hotel"]


# ---- Privatmodus (Nr. 61/63) ---------------------------------------------------------------------------------

def test_privatmodus_kein_get_mit_text(monkeypatch):
    ka = d.KeepAlive()
    u = d.urllib.parse.urlsplit("https://translate.googleapis.com/translate_a/single?client=gtx&q=geheim")
    ka.no_post["translate.googleapis.com"] = time.monotonic() + 60
    assert ka._split(u)[0] == "GET"                        # ohne Privatmodus: Rückfall wie bisher
    monkeypatch.setitem(d.PRIVATE, "on", True)
    with pytest.raises(urllib.error.URLError):
        ka._split(u)


def test_privatmodus_post_abgelehnt_wirft_statt_get(monkeypatch):
    monkeypatch.setitem(d.PRIVATE, "on", True)
    ka = d.KeepAlive()

    class Resp:
        status, reason, headers, will_close = 405, "nope", {}, True

        def read(self):
            return b""

    class Conn:
        sock = None
        timeout = None

        def request(self, method, path, body=None, headers=None):
            assert method == "POST" and "geheim" not in path

        def getresponse(self):
            return Resp()

        def close(self):
            pass

    monkeypatch.setattr(ka, "_take", lambda host, timeout: (Conn(), False))
    with pytest.raises(urllib.error.HTTPError) as ei:
        ka.get_json("https://translate.googleapis.com/translate_a/single?client=gtx&q=geheim", 2)
    assert "geheim" not in str(ei.value.filename)


def test_private_flag_existiert():
    src = open(d.__file__, encoding="utf-8").read()
    assert 'add_argument("--private"' in src and 'PRIVATE["on"] = bool(a.private)' in src


# ---- MyMemory (Nr. 56, 64) -----------------------------------------------------------------------------------

def _mm(monkeypatch, match, seen=None):
    def fake(url, timeout):
        if seen is not None:
            seen.append(url)
        return {"responseStatus": 200, "responseData": {"translatedText": "สวัสดี", "match": match}}
    monkeypatch.setattr(d, "_get_json", fake)


def test_mymemory_schwacher_treffer_abgelehnt(monkeypatch):
    _mm(monkeypatch, 0.2)
    with pytest.raises(RuntimeError, match="schwacher Treffer"):
        d.mymemory_translate("hello", "en", "th")


@pytest.mark.parametrize("match", [0.5, 0.85, 1, None, "x"])
def test_mymemory_guter_oder_fehlender_treffer(monkeypatch, match):
    _mm(monkeypatch, match)
    assert d.mymemory_translate("hello", "en", "th") == "สวัสดี"


def test_mymemory_email_parameter(monkeypatch):
    seen = []
    _mm(monkeypatch, 1, seen)
    monkeypatch.setenv("DOLMETSCHER_MYMEMORY_EMAIL", "a@b.example")
    d.mymemory_translate("hello", "en", "th")
    monkeypatch.setenv("DOLMETSCHER_MYMEMORY_EMAIL", "kein-mail&x=1")
    d.mymemory_translate("hello", "en", "th")
    monkeypatch.delenv("DOLMETSCHER_MYMEMORY_EMAIL")
    d.mymemory_translate("hello", "en", "th")
    assert seen[0].endswith("&de=a%40b.example")
    assert "&de=" not in seen[1] and "&de=" not in seen[2]


# ---- Log-Rotation (Nr. 71), CPU-Threads (Nr. 47), wait_quiet (Nr. 30) -----------------------------------------

@pytest.mark.parametrize("env, want", [
    ({}, (1.0, 3)),
    ({"DOLMETSCHER_LOG_MB": "5", "DOLMETSCHER_LOG_BACKUPS": "4"}, (5.0, 4)),
    ({"DOLMETSCHER_LOG_MB": "999", "DOLMETSCHER_LOG_BACKUPS": "0"}, (50.0, 1)),
    ({"DOLMETSCHER_LOG_MB": "nan", "DOLMETSCHER_LOG_BACKUPS": "x"}, (1.0, 3)),
])
def test_log_rotation(env, want):
    assert d.log_rotation(env) == want


def test_perf_cores():
    vals = {"hw.perflevel0.physicalcpu": "8", "hw.physicalcpu": "12"}

    def run(cmd, **kw):
        return types.SimpleNamespace(returncode=0, stdout=vals.get(cmd[-1], ""))
    assert hwprofile.perf_cores(run) == 8
    vals.pop("hw.perflevel0.physicalcpu")
    assert hwprofile.perf_cores(run) == 12
    assert hwprofile.perf_cores(lambda cmd, **kw: types.SimpleNamespace(returncode=1, stdout="")) == 0


def test_cpu_kw(monkeypatch):
    monkeypatch.setattr(hwprofile, "perf_cores", lambda run=None: 6)
    monkeypatch.delenv("DOLMETSCHER_CPU_THREADS", raising=False)
    assert d.cpu_kw() == {"cpu_threads": 6}
    monkeypatch.setenv("DOLMETSCHER_CPU_THREADS", "3")
    assert d.cpu_kw() == {"cpu_threads": 3}
    monkeypatch.setenv("DOLMETSCHER_CPU_THREADS", "0")
    monkeypatch.setattr(hwprofile, "perf_cores", lambda run=None: 0)
    assert d.cpu_kw() == {}


def test_wait_quiet_grenze_ist_max_utt(monkeypatch):
    t = [0.0]
    monkeypatch.setattr(d.time, "time", lambda: t[0])
    monkeypatch.setattr(d.time, "sleep", lambda s: t.__setitem__(0, t[0] + 1.0))
    monkeypatch.setattr(d, "BARGE_IN", False)
    d.HEARING.set()
    try:
        assert d.wait_quiet() == pytest.approx(d.MAX_UTT, abs=1.0)
        assert d.wait_quiet(limit=2) == pytest.approx(2, abs=1.0)
    finally:
        d.HEARING.clear()


# ---- Audio für "Das war ich/sie" läuft ab (Nr. 174) ------------------------------------------------------------

def test_recent_audio_laeuft_ab(monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(d.time, "monotonic", lambda: now[0])
    eng = d.Engine.__new__(d.Engine)
    eng._remember("a", np.zeros(10, dtype=np.float32), None)
    now[0] += d.RECENT_TTL - 1
    eng._remember("b", np.zeros(10, dtype=np.float32), None)
    assert list(eng.recent) == ["a", "b"]
    now[0] += 2
    eng._expire_recent()
    assert list(eng.recent) == ["b"]


def test_reassign_nach_ablauf_meldet_expired(monkeypatch, capsys):
    now = [0.0]
    monkeypatch.setattr(d.time, "monotonic", lambda: now[0])
    monkeypatch.setattr(d, "JSON", True)
    eng = d.Engine.__new__(d.Engine)
    eng._remember("a", np.zeros(10, dtype=np.float32), None)
    now[0] += d.RECENT_TTL + 1
    eng.reassign("a", "me")
    assert [e.get("code") for e in _events(capsys)] == ["reassign_expired"]


# ---- VAD-Selbsttest (Nr. 194) ------------------------------------------------------------------------------------

def test_vad_selbsttest_meldet_fehler(monkeypatch, capsys):
    monkeypatch.setattr(d, "JSON", True)

    def boom(self):
        raise ImportError("get_vad_model fehlt")
    monkeypatch.setattr(d.StreamVAD, "__init__", boom)
    assert d.vad_selftest() is False
    assert [e.get("code") for e in _events(capsys)] == ["vad_failed"]


def test_vad_selbsttest_ok(monkeypatch):
    class Sess:
        def run(self, _, feed):
            return np.array([[0.01]], dtype=np.float32), feed["h"], feed["c"]

    def init(self):
        self.sess = Sess()
        self.reset()
    monkeypatch.setattr(d.StreamVAD, "__init__", init)
    assert d.vad_selftest() is True


# ---- Verlauf: Schema-Version (Nr. 207) und Grenzfälle (Nr. 208) ----------------------------------------------------

def test_history_schema_version(tmp_path):
    s = hs.Store(str(tmp_path / "h.sqlite"))
    assert s.db.execute("PRAGMA user_version").fetchone()[0] == hs.SCHEMA_VERSION
    s.close()
    s = hs.Store(str(tmp_path / "h.sqlite"))              # erneutes Öffnen: unverändert
    assert s.db.execute("PRAGMA user_version").fetchone()[0] == hs.SCHEMA_VERSION
    s.db.execute("PRAGMA user_version = 99")
    s.db.commit()
    s.close()
    with pytest.raises(RuntimeError, match="Schema 99"):
        hs.Store(str(tmp_path / "h.sqlite"))


@pytest.mark.parametrize("days", [0, -1, float("inf"), float("nan")])
def test_history_purge_ungueltig_loescht_nichts(tmp_path, days):
    s = hs.Store(str(tmp_path / "h.sqlite"))
    s.add("alt", ts=time.time() - 400 * 86400)
    with pytest.raises(ValueError):
        s.purge(days)
    assert s.db.execute("SELECT COUNT(*) FROM utt").fetchone()[0] == 1


def test_history_suche_begrenzt(tmp_path):
    s = hs.Store(str(tmp_path / "h.sqlite"))
    for i in range(1205):
        s.add(f"hallo {i}", ts=1000.0 + i)
    hits = s.search("hallo", limit=1000)
    assert len(hits) == 1000


def test_history_datei_rechte(tmp_path):
    p = tmp_path / "h.sqlite"
    hs.Store(str(p)).close()
    assert stat.S_IMODE(os.stat(p).st_mode) == 0o600


# ---- Zahlenvergleich als Tabelle (Nr. 58) ---------------------------------------------------------------------------

@pytest.mark.parametrize("a, b, differ", [
    ("It costs 1,500 baht", "ราคา 1500 บาท", False),
    ("It costs 1.500 baht", "ราคา 1,500 บาท", False),
    ("Meet at 2:30 PM", "เจอกัน 14:30", False),
    ("Room 305 please", "ห้อง 350 ครับ", True),
    ("It costs 250 baht", "ราคา 520 บาท", True),
    ("Call 0812345678", "โทร 0812345678", False),
    ("555 so funny", "ตลกมาก", False),
    ("It is 1.5 million", "1500000", False),
])
def test_numbers_differ_tabelle(a, b, differ):
    assert d.numbers_differ(a, b) is differ


# ---- decide_role als Tabelle (Nr. 199) ------------------------------------------------------------------------------

M = profiles.ROLE_ME_MIN


@pytest.mark.parametrize("sim_me, sim_her, dur, prev, want", [
    (M, None, 2.0, None, "me"),                                   # genau auf der Schwelle: ich
    (M - 0.001, None, 2.0, None, None),                           # knapp darunter, kein Vorgänger: unklar
    (profiles.ROLE_OTHER_MAX, None, 1.0, None, "other"),           # kurz: sicher andere Stimme
    (profiles.ROLE_OTHER_MAX_LONG, None, 2.0, None, "other"),      # lang: höhere Grenze
    (profiles.ROLE_OTHER_MAX_LONG, None, 1.0, None, None),         # kurz und darüber: Graubereich
    (0.70, None, 2.0, "me", "me"),                                # Graubereich + vorher ich
    (0.80, 0.60, 2.0, None, "me"),                                # mit Partnerprofil: ich klar vorn
    (0.40, 0.70, 2.0, None, "other"),                             # Partner klar vorn
    (0.60, 0.61, 2.0, None, None),                                # zu knapp, kein Vorgänger
    (0.60, 0.64, 2.0, "other", "other"),                          # knapp + vorher Partner
])
def test_decide_role_tabelle(sim_me, sim_her, dur, prev, want):
    role, _why = profiles.decide_role(sim_me, sim_her, dur, M, prev)
    assert role == want
