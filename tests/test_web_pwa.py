"""Web-Version als PWA: Manifest, Service Worker, Icons, Offline-Satzbuch – statisch geprüft."""
import json
import pathlib
import re
import shutil
import struct
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SW = (ROOT / "sw.js").read_text(encoding="utf-8")
MANIFEST = json.loads((ROOT / "manifest.webmanifest").read_text(encoding="utf-8"))


def _js_list(src, name):
    m = re.search(r"const " + name + r" = \[([^\]]*)\]", src)
    assert m, name
    return re.findall(r"'([\w.-]+)'", m.group(1))


def test_manifest_installable():
    for k in ("name", "short_name", "start_url", "scope", "display", "theme_color", "background_color"):
        assert MANIFEST.get(k), k
    assert MANIFEST["display"] in ("standalone", "fullscreen", "minimal-ui")
    assert MANIFEST["start_url"] == "./" and MANIFEST["scope"] == "./"   # relativ: GitHub Pages unter /<repo>/
    sizes = {i["sizes"] for i in MANIFEST["icons"]}
    assert {"192x192", "512x512"} <= sizes
    for i in MANIFEST["icons"]:
        assert (ROOT / i["src"]).is_file(), i["src"]
        if i["type"] == "image/png":
            data = (ROOT / i["src"]).read_bytes()
            assert data[:8] == b"\x89PNG\r\n\x1a\n"
            w, h = struct.unpack(">II", data[16:24])
            assert f"{w}x{h}" == i["sizes"], i["src"]
    assert MANIFEST["theme_color"] in HTML                 # meta theme-color passt


def test_html_links_manifest_and_registers_sw():
    assert '<link rel="manifest" href="manifest.webmanifest">' in HTML
    assert 'rel="icon"' in HTML and 'name="theme-color"' in HTML
    assert "navigator.serviceWorker.register('sw.js')" in HTML
    assert "window.isSecureContext" in HTML               # file:// und http-Fremdhosts: kein Versuch


def test_preset_lists_match_directory():
    files = sorted(p.stem for p in (ROOT / "presets").glob("*.json"))
    assert sorted(_js_list(SW, "PRESET_IDS")) == files
    assert sorted(_js_list(HTML, "PRESET_IDS")) == files


def test_presets_have_phrases_for_cards():
    for p in (ROOT / "presets").glob("*.json"):
        d = json.loads(p.read_text(encoding="utf-8"))
        assert d["phrases"], p.name
        assert all(ph.get("en") and ph.get("th") for ph in d["phrases"]), p.name
        assert d["names"].get("de"), p.name


def test_sw_caches_core_files_that_exist():
    core = _js_list(SW, "CORE")
    for f in core:
        if f != "./":
            assert (ROOT / f).is_file(), f
    assert "index.html" in core and "manifest.webmanifest" in core
    assert "'presets/' + id + '.json'" in SW


def test_sw_never_touches_foreign_requests():
    fetch = SW.split("addEventListener('fetch'", 1)[1]
    assert "req.method !== 'GET'" in fetch
    assert "url.origin !== self.location.origin) return;" in fetch
    assert fetch.index("self.location.origin") < fetch.index("respondWith")
    assert "googleapis.com" not in SW and "mymemory.translated" not in SW
    assert "self.registration.scope" in SW                 # Pfade relativ zum Scope
    assert "caches.delete" in SW and "skipWaiting" in SW and "clients.claim" in SW


def test_offline_hint():
    assert 'id="offline"' in HTML
    assert "addEventListener('offline'" in HTML and "addEventListener('online'" in HTML


def test_no_trackers_or_new_hosts():
    hosts = set(re.findall(r"https://([\w.-]+)", HTML + SW + json.dumps(MANIFEST)))
    assert hosts <= {"translate.googleapis.com", "api.mymemory.translated.net", "github.com"}, hosts


@pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")
def test_sw_syntax(tmp_path):
    js = tmp_path / "sw.js"
    js.write_text(SW, encoding="utf-8")
    r = subprocess.run(["node", "--check", str(js)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
