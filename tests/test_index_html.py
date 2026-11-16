"""Web Lite (index.html): Syntax und kritische Muster prüfen – ohne Browser, ohne neue Abhängigkeit."""
import pathlib
import re
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SCRIPT = re.search(r"<script>(.*?)</script>", HTML, re.S).group(1)


def func(name):
    """Rumpf einer Top-Level-Funktion (bis zur nächsten Zeile, die mit } beginnt)."""
    m = re.search(r"^(?:async )?function " + name + r"\(.*?^\}", SCRIPT, re.S | re.M)
    assert m, name
    return m.group(0)


@pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")
def test_script_syntax(tmp_path):
    js = tmp_path / "index.js"
    js.write_text(SCRIPT, encoding="utf-8")
    r = subprocess.run(["node", "--check", str(js)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr


def test_no_external_scripts_and_strict_csp():
    assert "<script src" not in HTML
    csp = re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', HTML).group(1)
    assert "default-src 'none'" in csp
    hosts = set(re.findall(r"https://[\w.-]+", csp.split("connect-src", 1)[1].split(";", 1)[0]))
    assert hosts == {"https://translate.googleapis.com", "https://api.mymemory.translated.net"}


def test_pause_stops_recognition():
    body = re.search(r"if \(cmd === 'pause'\) \{(.*?)\n  \}", SCRIPT, re.S).group(1)
    assert "setMode(null)" in body                       # Modus aus = kein Neustart-Pfad mehr
    assert "resumeIfIdle" not in body and "startRec" not in body
    assert "Translator resume" not in HTML               # wird nicht mehr versprochen (Mikrofon ist aus)


def test_consent_before_microphone():
    assert '<dialog id="consent"' in HTML
    choose = func("chooseMode")
    assert "hasConsent()" in choose and "showModal" in choose
    # Jeder Mikrofon-Start durch Nutzer läuft über chooseMode, nicht direkt über setMode.
    assert "btn.onclick = () => chooseMode(" in SCRIPT
    assert "e.code === 'KeyE') chooseMode('en')" in SCRIPT and "e.code === 'KeyT') chooseMode('th')" in SCRIPT
    assert "localStorage.setItem('micConsent'" in func("acceptConsent")
    assert "if (consentOpen()) return;" in SCRIPT.split("document.addEventListener('keydown'", 1)[1]


def test_mymemory_errors_and_entities():
    one = func("translateOne")
    assert "decodeEntities(" in one and "throw new Error('mymemory unavailable')" in one
    for pat in ("MYMEMORY WARNING", "QUERY LENGTH LIMIT", "INVALID LANGUAGE", "quotaFinished", "responseStatus"):
        assert pat in one
    google = one.split("catch (e)", 1)[0]
    assert "decodeEntities" not in google                # Google-Text wird nicht verändert
    # Dekodieren über ein <textarea> (parst nur Text, führt nichts aus), Ergebnis landet per textContent im DOM.
    assert "document.createElement('textarea')" in SCRIPT and "entityBox.value" in func("decodeEntities")


def test_translation_errors_never_spoken():
    d = func("deliver")
    assert "out === null" in d                           # Fehlerfall: nichts vorlesen
    assert "lastOut = " in d.split("}, () => {", 1)[0]   # nur echte Übersetzungen sind „repeat“-fähig


def test_accessibility():
    assert re.search(r'id="announce"[^>]*aria-live="polite"', HTML)
    assert re.search(r'id="log"[^>]*aria-live="off"', HTML)   # sonst doppelte bzw. „…“-Ansagen
    assert "announce(out, m.to)" in func("deliver")
    assert 'aria-labelledby="consentTitle"' in HTML
    assert '<html lang="de">' in HTML and 'name="viewport"' in HTML
    for m in re.finditer(r"<button\b[^>]*>(.*?)</button>", HTML, re.S):
        assert re.sub(r"<[^>]+>", "", m.group(1)).strip(), m.group(0)   # kein Knopf ohne Beschriftung
    for m in re.finditer(r'<input\b[^>]*id="(\w+)"', HTML):
        assert re.search(r"<label><input\b[^>]*id=\"" + m.group(1) + '"', HTML), m.group(1)
    assert "min-height:44px" in HTML                      # Fingertipp-Ziele auf dem Handy


def test_warnings_can_be_cleared():
    assert "function clearWarn" in SCRIPT and "r.onstart = () => clearWarn(" in SCRIPT
