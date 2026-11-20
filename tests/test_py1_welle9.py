"""Runde 21 (py1) Welle 9."""
import dolmetscher as d


def test_helper_error_never_logs_text():
    assert d.helper_error("timeout") == "timeout"
    assert d.helper_error("notInstalled(en->th)") == "notInstalled"
    secret = "Fehler bei 'my secret sentence'"
    assert d.helper_error(secret) == "helper-fehler" and "secret" not in d.helper_error(secret)
    assert d.helper_error(None) == "" and d.helper_error(5) == ""


def test_offline_helper_gets_pairs(monkeypatch):
    import dolmetscher as d
    cmds = []

    class P:
        stdin = type("S", (), {"write": lambda s, b: None, "flush": lambda s: None})()
        stdout = None

        def poll(self):
            return None

        def kill(self):
            pass

    m = d.OfflineMT()
    m.path, m.on = "/x/helper", True
    monkeypatch.setattr(d.subprocess, "Popen", lambda cmd, **k: cmds.append(cmd) or P())
    monkeypatch.setattr(m, "_readline", lambda t: {"ready": True, "pairs": {"en-th": "installed"}})
    assert m._start(("en", "th"))
    assert cmds[-1][1:] == ["--pairs", "en-th,th-en"]
    assert m._start(("th", "en")) and len(cmds) == 1      # Gegenrichtung: kein Neustart
    assert m._start(("en", "de")) and len(cmds) == 2      # anderes Paar: Neustart
    assert cmds[-1][2] == "en-de,de-en"


def test_travel_place_case_sensitive():
    import dolmetscher as d
    t, slots = d._protect("meet at the siam paragon", "th")
    assert "[1]" not in t or "Siam" not in slots
    t, slots = d._protect("meet at Siam square", "th")
    assert slots
