"""Runde 22 (Engine): utt-Ereignisse je uid idempotent, Verlauf ohne Doppelzeile, Thai-Pronomen, Hilfsfunktionen."""
import collections
import io
import types

import pytest

import dolmetscher as d
import history_store


@pytest.fixture(autouse=True)
def _frisch():
    d._UTT_SEEN.clear()
    yield
    d._UTT_SEEN.clear()


def _echtes_emit(monkeypatch):
    got = []
    monkeypatch.setattr(d, "_emit", lambda e, **kw: got.append((e, kw)))
    monkeypatch.setattr(d, "_record", lambda e, kw: None)
    return got


def test_emit_utt_doppelt_wird_einmal_gemeldet(monkeypatch):
    got = _echtes_emit(monkeypatch)
    d.emit("utt", id="u1", to="th", out="สวัสดี", text="hello")
    d.emit("utt", id="u1", to="th", out="สวัสดี", text="hello")
    assert [e for e, _ in got].count("utt") == 1


def test_emit_utt_andere_fassung_gleicher_uid_wird_gemeldet(monkeypatch):
    got = _echtes_emit(monkeypatch)
    d.emit("utt", id="u1", to="th", out="a")
    d.emit("utt", id="u1", to="th", out="b")
    assert [e for e, _ in got].count("utt") == 2


def test_emit_andere_ereignisse_nie_unterdrueckt(monkeypatch):
    got = _echtes_emit(monkeypatch)
    for _ in range(3):
        d.emit("listening")
        d.emit("partial", id="u1", text="x", lang="en")
    assert len(got) == 6


def test_utt_seen_ist_begrenzt():
    for i in range(d._UTT_SEEN_MAX + 50):
        d._utt_duplicate({"id": f"u{i}", "to": "th", "out": "x"})
    assert len(d._UTT_SEEN) == d._UTT_SEEN_MAX


def test_utt_ohne_id_ist_nie_duplikat():
    assert not d._utt_duplicate({"to": "th", "out": "x"})
    assert not d._utt_duplicate({"to": "th", "out": "x"})


def _engine(monkeypatch):
    import os, sys
    sys.path.insert(0, os.path.dirname(__file__))
    from test_engine_pipeline import _engine
    e = _engine([("en", 0.9)], {"en": ("x", -0.1)})
    adds = []
    e.speaker = types.SimpleNamespace(add=lambda *a, **k: adds.append(a))
    e._adds = adds
    return e


def test_deliver_gleiche_uid_zweimal_spricht_und_meldet_einmal(monkeypatch):
    got = _echtes_emit(monkeypatch)
    monkeypatch.setitem(d.LLM, "on", False)
    n = []
    monkeypatch.setattr(d, "translate", lambda *a, **k: n.append(1) or "ห้องน้ำอยู่ไหน")
    e = _engine(monkeypatch)
    r1 = e.deliver("uX", "en", "Where is the toilet", speak=True)
    r2 = e.deliver("uX", "en", "Where is the toilet", speak=True)
    assert r1 == r2
    assert len(n) == 1 and len(e._adds) == 1
    assert [x for x, _ in got].count("utt") == 1
    assert len(e.history) == 1


def test_deliver_korrektur_mit_neuer_uid_laeuft_weiter(monkeypatch):
    got = _echtes_emit(monkeypatch)
    monkeypatch.setitem(d.LLM, "on", False)
    monkeypatch.setattr(d, "translate", lambda text, *a, **k: "ก:" + text)
    e = _engine(monkeypatch)
    e.deliver("u1", "en", "Where is the toilet", speak=False)
    e.deliver("u2", "en", "Where is the station", speak=False, replaces="u1")
    assert [x for x, _ in got].count("utt") == 2
    assert [h[1] for h in e.history] == ["Where is the station"]


def test_trim_oldest_haelt_reihenfolge_und_grenze():
    o = collections.OrderedDict((i, i) for i in range(10))
    d._trim_oldest(o, 3)
    assert list(o) == [7, 8, 9]
    d._trim_oldest({}, 3)


@pytest.mark.parametrize("src, out", [
    ("แต่ผมไม่รู้", "แต่ฉันไม่รู้"),
    ("ถ้าผมไปด้วย", "ถ้าฉันไปด้วย"),
    ("เพราะผมเหนื่อย", "เพราะฉันเหนื่อย"),
    ("และผมสั้น", "และผมสั้น"),            # Haar bleibt
    ("ผมยาว", "ผมยาว"),
])
def test_fix_thai_frau_pronomen_nach_konjunktion(src, out):
    assert d.fix_thai(src, "ka") == out


def test_fix_thai_mann_bleibt_ohne_aenderung():
    assert d.fix_thai("แต่ผมไม่รู้ครับ", "krub") == "แต่ผมไม่รู้ครับ"


def test_history_add_gleiche_uid_keine_doppelzeile(tmp_path):
    s = history_store.Store(str(tmp_path / "h.sqlite"))
    a = s.add("hi", "สวัสดี", lang="en", uid="u1", session="s")
    b = s.add("hi", "สวัสดี", lang="en", uid="u1", session="s")
    assert a == b and len(s.rows()) == 1
    s.add("hi", "หวัดดี", lang="en", uid="u1", session="s")      # andere Übersetzung: eigene Zeile
    assert len(s.rows()) == 2
    s.close()


def test_avhelper_write_geschlossene_pipe_beendet_leise(monkeypatch):
    import avhelper

    class Pipe(io.RawIOBase):
        def write(self, b):
            raise BrokenPipeError

        def fileno(self):
            raise OSError

    out = types.SimpleNamespace(buffer=Pipe(), fileno=lambda: (_ for _ in ()).throw(OSError()))
    monkeypatch.setattr(avhelper.sys, "stdout", out)
    with pytest.raises(SystemExit) as ei:
        avhelper._write(b"abc")
    assert ei.value.code == 0
