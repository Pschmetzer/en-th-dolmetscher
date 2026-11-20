"""Runde 23 (Infrastruktur): tools/pages_smoke.py gegen einen lokalen Server mit dem Repository als Wurzel."""
import functools
import http.server
import importlib.util
import pathlib
import threading

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _load():
    spec = importlib.util.spec_from_file_location("pages_smoke", ROOT / "tools" / "pages_smoke.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


smoke = _load()


class _Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a, **kw):
        pass


@pytest.fixture(scope="module")
def base():
    handler = functools.partial(_Quiet, directory=str(ROOT))
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    yield f"http://127.0.0.1:{srv.server_address[1]}/"
    srv.shutdown()
    srv.server_close()


def test_lokale_seite_besteht_den_smoke_test(base):
    assert smoke.check(base, sample=5) == []


def test_main_ok_und_fehlercode(base, capsys):
    assert smoke.main([base, "--sample", "2"]) == 0
    assert "OK:" in capsys.readouterr().out
    assert smoke.main([base + "gibt-es-nicht/", "--sample", "1"]) == 1


def test_fehlende_datei_wird_gemeldet(base):
    errors = smoke.check(base + "unterordner/", sample=1)
    assert errors and any("index.html" in e for e in errors)


def test_cache_version_des_repos_wird_erkannt(base):
    v = smoke.local_cache_version()
    assert v and v.startswith("dolmetscher-web-v")
    assert smoke.wait_for_deploy(base, v, wait=5, interval=0.1) is True
    assert smoke.wait_for_deploy(base, "dolmetscher-web-v0", wait=0, interval=0.1) is False


def test_nur_http_adressen(capsys):
    with pytest.raises(SystemExit):
        smoke.main(["file:///etc/passwd"])


def test_kern_dateien_gibt_es_im_repo():
    for f in smoke.CORE:
        assert (ROOT / f).is_file(), f
