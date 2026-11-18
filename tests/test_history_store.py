import json
import os
import stat

import pytest

import history_store as hs

T0 = 1_700_000_000.0


@pytest.fixture
def st(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path / "home"))
    s = hs.Store()
    s.add("Hello there", "สวัสดี", lang="en", translit=None, conf=0.9, provider="google", session="s1", ts=T0)
    s.add("ไปไหนครับ", "Where are you going?", lang="th", translit="pai nai khrap", conf=0.5,
          provider="claude", session="s1", ts=T0 + 4.0)
    s.add("Old one", "เก่า", lang="en", session="s0", ts=T0 - 90 * 86400)
    yield s
    s.close()


def test_permissions(st):
    d = os.path.dirname(st.path)
    assert stat.S_IMODE(os.stat(d).st_mode) == 0o700
    assert stat.S_IMODE(os.stat(st.path).st_mode) == 0o600
    assert st.path.startswith(os.environ["DOLMETSCHER_HOME"])


def test_export_json_csv_exact(st):
    rows = st.rows("s1")
    j = json.loads(hs.export(rows, "json"))
    assert j[1] == {"time": "2023-11-14T22:13:24.000Z", "session": "s1", "lang": "th", "text": "ไปไหนครับ",
                    "translation": "Where are you going?", "translit": "pai nai khrap",
                    "confidence": 0.5, "provider": "claude"}
    assert hs.export(rows, "csv").splitlines() == [
        "time,session,lang,text,translation,translit,confidence,provider",
        "2023-11-14T22:13:20.000Z,s1,en,Hello there,สวัสดี,,0.9,google",
        "2023-11-14T22:13:24.000Z,s1,th,ไปไหนครับ,Where are you going?,pai nai khrap,0.5,claude"]


def test_export_srt_vtt_exact(st):
    rows = st.rows("s1")
    assert hs.export(rows, "srt") == (
        "1\n00:00:00,000 --> 00:00:01,500\nHello there\nสวัสดี\n\n"
        "2\n00:00:04,000 --> 00:00:05,500\nไปไหนครับ\nWhere are you going?\n")
    assert hs.export(rows, "vtt").startswith("WEBVTT\n\n00:00:00.000 --> 00:00:01.500\n")


def test_export_md_anki_exact(st):
    rows = st.rows("s1")
    assert hs.export(rows, "md") == (
        "# Gesprächsverlauf\n\n## Sitzung s1 (2023-11-14T22:13:20.000Z)\n\n"
        "- **22:13:20** [EN] Hello there\n  → สวัสดี\n"
        "- **22:13:24** [TH] ไปไหนครับ\n  → Where are you going? (pai nai khrap)\n")
    anki = hs.export(rows, "anki").split("\n")              # Runde 7: mit GUID, Stapel und Tags (erneuter Import)
    assert anki[:5] == ["#separator:tab", "#html:false", "#guid column:1", "#deck:Dolmetscher", "#tags column:5"]
    f1, f2 = anki[5].split("\t"), anki[6].split("\t")
    assert f1[1:4] == ["Hello there", "สวัสดี", ""] and f1[4] == "lang_en session_s1"
    assert f2[1:4] == ["ไปไหนครับ", "Where are you going?", "pai nai khrap"] and f1[0] != f2[0]
    assert hs.export(rows, "anki") == "\n".join(anki)         # GUIDs sind stabil


def test_purge_and_clear(st):
    st.add("fresh", "neu", lang="en", session="s2")             # Zeit = jetzt
    assert st.purge(30) == 3
    assert [r["text"] for r in st.rows()] == ["fresh"]
    assert st.search("Hello") == []
    assert st.clear() == 1
    assert st.rows() == [] and st.search("Hello") == []


def test_search_thai_and_short(st):
    assert [r["text"] for r in st.search("ไหน")] == ["ไปไหนครับ"]
    assert [r["text"] for r in st.search("going")] == ["ไปไหนครับ"]
    assert [r["text"] for r in st.search("ll")] == ["Hello there"]     # kurz: LIKE
    assert st.search("100%") == []


def test_recorder_off_by_default_and_on(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path / "h"))
    r = hs.Recorder()
    r.utt({"text": "hi", "out": "x", "translated": True})
    assert not os.path.exists(hs.db_path())                 # aus: nichts angelegt
    r.enable(True)
    r.utt({"id": "u1", "text": "hi", "out": "สวัสดี", "translated": True, "lang": "en", "lp": -0.1, "provider": "g"})
    r.utt({"id": "u2", "text": "hi!", "out": "สวัสดี", "translated": True, "lang": "en", "replaces": "u1"})
    assert [x["text"] for x in r.store.rows()] == ["hi!"]
    r.enable(False)
    r.utt({"text": "nope", "out": "x", "translated": True})
    assert len(r.store.rows()) == 1


def test_gleichzeitiges_schreiben_aus_threads(tmp_path):
    """Nr. 204: eine Verbindung, mehrere Threads – jede Zeile genau einmal, Suchindex passt dazu."""
    import threading
    s = hs.Store(str(tmp_path / "h.sqlite"))

    def worker(n):
        for i in range(50):
            s.add(f"t{n}-{i}", "x", lang="en", uid=f"u{n}-{i}")
    ts = [threading.Thread(target=worker, args=(n,)) for n in range(4)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert len(s.rows()) == 200
    if s.fts:
        assert s.db.execute("SELECT count(*) FROM utt_fts").fetchone()[0] == 200
    s.add("neu", "y", uid="n1", replaces="u0-0")       # Ersetzen + Einfügen in einer Transaktion
    assert len(s.rows()) == 200 and not [r for r in s.rows() if r["uid"] == "u0-0"]
    s.close()
