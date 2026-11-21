"""Runde 27: Ausgabegerät je Richtung (output_device_me / output_device_other), additiv in der Engine."""
import pathlib
import threading
import types

import pytest

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


@pytest.fixture(autouse=True)
def _reset(monkeypatch):
    monkeypatch.setattr(d, "OUTPUT", {"device": "", "me": "", "other": ""})
    monkeypatch.setattr(d, "FFMPEG", None)
    monkeypatch.setattr(d, "PAIR", ["de", "th"])


def _eng():
    return types.SimpleNamespace(translate_dir={"de": True, "th": True}, lock="auto", polite="krub", mute=False,
                                 paused=False, rate=0, volume=1.0, voices={}, earcons=False)


def test_route_by_target_language():
    assert d.output_route("de", "u1") == "me"
    assert d.output_route("th", "u1") == "other"
    assert d.output_route("fr", "u1") == "other"          # dritte Sprache wie Partnersprache
    assert d.output_route("th", "cmd") == "me"            # Befehlsantworten gehen immer an mich
    assert d.output_route(None, None) == "other"


def test_device_now_falls_back_to_general_device():
    d.OUTPUT.update(device="Lautsprecher")
    d._ROUTE.dir = "me"
    try:
        assert d.output_device_now() == "Lautsprecher"
        d.OUTPUT["me"] = "AirPods"
        assert d.output_device_now() == "AirPods"
        d._ROUTE.dir = "other"
        assert d.output_device_now() == "Lautsprecher"
        d.OUTPUT["other"] = "BoomBox"
        assert d.output_device_now() == "BoomBox"
    finally:
        d._ROUTE.dir = None
    assert d.output_device_now() == "Lautsprecher"


def test_route_is_thread_local():
    d._ROUTE.dir = "me"
    seen = []
    t = threading.Thread(target=lambda: seen.append(getattr(d._ROUTE, "dir", None)))
    t.start()
    t.join()
    d._ROUTE.dir = None
    assert seen == [None]


def test_file_play_cmd_uses_route_device(monkeypatch):
    monkeypatch.setattr(d, "avhelper_cmd", lambda *a: ["avh", *a])
    d.OUTPUT.update(me="AirPods", other="BoomBox")
    d._ROUTE.dir = "other"
    try:
        cmd = d.file_play_cmd("/tmp/x.aiff", 1.0)
        assert cmd[-2:] == ["--device", "BoomBox"]
        d._ROUTE.dir = "me"
        assert d.file_play_cmd("/tmp/x.aiff", 1.0)[-2:] == ["--device", "AirPods"]
        d._ROUTE.dir = None
        assert d.file_play_cmd("/tmp/x.aiff", 1.0)[0] == d.AFPLAY       # nichts gesetzt: afplay wie bisher
    finally:
        d._ROUTE.dir = None


def test_pipe_player_uses_route_device(monkeypatch):
    monkeypatch.setattr(d, "avhelper_cmd", lambda *a: ["avh", *a])
    d.OUTPUT["me"] = "AirPods"
    d._ROUTE.dir = "me"
    try:
        assert d.pipe_player(1.0)[-2:] == ["--device", "AirPods"]
    finally:
        d._ROUTE.dir = None
    assert "--device" not in d.pipe_player(1.0)


def test_play_sets_and_clears_route(monkeypatch, ev):
    seen = []
    sp = d.Speaker.__new__(d.Speaker)
    monkeypatch.setattr(d.Speaker, "_play_routed", lambda self, it, gen=None: seen.append(d.output_device_now()))
    d.OUTPUT.update(me="AirPods", other="BoomBox")
    sp._play({"id": "u1", "lang": "th", "kind": "speech", "parts": []})
    sp._play({"id": "u2", "lang": "de", "kind": "speech", "parts": []})
    sp._play({"id": "cmd", "lang": "th", "kind": "speech", "parts": []})
    assert seen == ["BoomBox", "AirPods", "AirPods"]
    assert getattr(d._ROUTE, "dir", None) is None


def test_route_cleared_after_error(monkeypatch):
    sp = d.Speaker.__new__(d.Speaker)

    def boom(self, it, gen=None):
        raise RuntimeError("x")
    monkeypatch.setattr(d.Speaker, "_play_routed", boom)
    with pytest.raises(RuntimeError):
        sp._play({"id": "u1", "lang": "de"})
    assert getattr(d._ROUTE, "dir", None) is None


def test_control_fields(ev):
    eng = _eng()
    d.apply_control(eng, {"output_device_me": "AirPods Pro", "output_device_other": "uid:123"})
    assert d.OUTPUT["me"] == "AirPods Pro" and d.OUTPUT["other"] == "uid:123"
    d.apply_control(eng, {"output_device_me": "default"})
    assert d.OUTPUT["me"] == "" and d.OUTPUT["other"] == "uid:123"
    d.apply_control(eng, {"output_device_other": ""})
    assert d.OUTPUT["other"] == ""
    d.apply_control(eng, {"output_device_me": 5})
    assert ev[-1][1]["code"] == "output_invalid" and d.OUTPUT["me"] == ""
    d.apply_control(eng, {"output_device_other": "x" * 301})
    assert ev[-1][1]["code"] == "output_invalid" and d.OUTPUT["other"] == ""


def test_control_fields_independent_of_general_device(ev):
    eng = _eng()
    d.apply_control(eng, {"output_device": "Standard-Gerät", "output_device_me": "AirPods"})
    assert d.OUTPUT["device"] == "Standard-Gerät" and d.OUTPUT["me"] == "AirPods"


def test_unsupported_with_ffmpeg(monkeypatch, ev):
    monkeypatch.setattr(d, "FFMPEG", "/usr/bin/ffmpeg")
    d.set_output_route("me", "AirPods")
    assert ev and ev[-1][1]["code"] == "output_unsupported"


def test_set_output_route_rejects_unknown_direction():
    assert d.set_output_route("both", "x") is False
    assert d.OUTPUT["me"] == "" and d.OUTPUT["other"] == ""


def test_capabilities_and_ctrl_spec():
    caps = d.capabilities()
    assert "control:output_device_me" in caps and "control:output_device_other" in caps
    assert d.CTRL_SPEC["output_device_me"] is False and d.CTRL_SPEC["output_device_other"] is False   # nie ins Log


def test_documented_in_protocol():
    assert "`output_device_me`" in DOCS and "`output_device_other`" in DOCS and "Runde 27" in DOCS


def test_real_earcon_path_gets_direction_device(monkeypatch, ev):
    cmds = []
    monkeypatch.setattr(d.PLAYER, "run", lambda cmd, *a, **k: cmds.append(cmd))
    monkeypatch.setattr(d, "avhelper_cmd", lambda *a: ["avh", *a])
    monkeypatch.setattr(d, "wait_quiet", lambda **k: None)
    d.OUTPUT.update(me="AirPods", other="BoomBox")
    sp = d.Speaker.__new__(d.Speaker)
    sp.eng = _eng()
    sp._play({"id": "cmd", "lang": "en", "kind": "earcon", "parts": []})
    assert cmds[-1][-2:] == ["--device", "AirPods"]            # Signalton = Richtung "me"
    assert getattr(d._ROUTE, "dir", None) is None


def test_real_local_voice_path_gets_direction_device(monkeypatch, ev):
    cmds = []
    monkeypatch.setattr(d.PLAYER, "run", lambda cmd, *a, **k: cmds.append(cmd))
    monkeypatch.setattr(d, "avhelper_cmd", lambda *a: ["avh", *a])
    monkeypatch.setattr(d, "wait_quiet", lambda **k: None)
    monkeypatch.setattr(d, "run_cancellable", lambda cmd, **k: 0)
    monkeypatch.setattr(d, "note_spoken", lambda *a, **k: None)
    monkeypatch.setattr(d.os.path, "exists", lambda p: True)
    d.OUTPUT.update(me="AirPods", other="BoomBox")
    sp = d.Speaker.__new__(d.Speaker)
    from unittest.mock import MagicMock
    eng = MagicMock()
    eng.tts, eng.mute, eng.rate, eng.volume, eng.voice_for = "say", False, 0, 1.0, (lambda lang: "x")
    eng.speak = lambda text, lang, **kw: d.PLAYER.run(d.file_play_cmd("/x.aiff", 1.0))   # Engine.speak läuft im Speaker
    sp.eng = eng
    sp.volume = 1.0
    for lang, dev in (("th", "BoomBox"), ("de", "AirPods")):
        cmds.clear()
        sp._play({"id": "u1", "lang": lang, "kind": "speech", "text": "ok", "parts": [("ok", None)], "local": [None],
                  "boost": 0})
        assert cmds and cmds[-1][-2:] == ["--device", dev], (lang, cmds)


def test_set_output_route_checks_device_in_background(monkeypatch, ev):
    import time as _t
    import avhelper
    monkeypatch.setattr(d, "list_outputs", lambda: avhelper.parse_outputs(
        ["[1] MacBook Pro-Lautsprecher, BuiltInSpeakerDevice\n"]))
    d.set_output_route("other", "Weg")
    for _ in range(100):
        if any(k.get("code") == "output_not_found" for _, k in ev):
            break
        _t.sleep(0.02)
    assert any(k.get("code") == "output_not_found" for _, k in ev)
    assert d.OUTPUT["other"] == "Weg"                          # Gerät bleibt gesetzt (avhelper fällt auf Standard)
