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
    # PWA: nur eigene Dateien (Manifest, Service Worker, Presets, Icons) – keine weiteren Hosts
    for d in ("worker-src 'self'", "manifest-src 'self'", "img-src 'self' data:", "connect-src 'self' "):
        assert d in csp, d
    assert "*" not in csp


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
    assert "chooseMode(k); };" in SCRIPT and "if (!hasConsent()) { chooseMode(k); return; }" in func("pttStart")
    assert "if (SR) chooseMode('a')" in SCRIPT and "if (SR) chooseMode('b')" in SCRIPT
    keys = SCRIPT.split("document.addEventListener('keydown'", 1)[1]
    assert "setMode(" not in keys.split("if (mode) setMode(mode)")[0]   # Start nur über chooseMode (Einwilligung)
    assert "localStorage.setItem('micConsent'" in func("acceptConsent")
    assert "if (consentOpen()) return;" in SCRIPT.split("document.addEventListener('keydown'", 1)[1]


def test_mymemory_errors_and_entities():
    mm = func("viaMyMemory")
    assert "decodeEntities(" in mm and "throw new Error('mymemory unavailable')" in mm
    for pat in ("MYMEMORY WARNING", "QUERY LENGTH LIMIT", "INVALID LANGUAGE", "quotaFinished", "responseStatus"):
        assert pat in mm
    assert "decodeEntities" not in func("viaGoogle")     # Google-Text wird nicht verändert
    one = func("translateOne")
    assert "implausible(" in one and "viaGoogle(" in one and "viaMyMemory(" in one
    assert "mapLimit(" in func("translate")             # Stücke mit begrenzter Parallelität
    # Dekodieren über ein <textarea> (parst nur Text, führt nichts aus), Ergebnis landet per textContent im DOM.
    assert "document.createElement('textarea')" in SCRIPT and "entityBox.value" in func("decodeEntities")


def test_translation_errors_never_spoken():
    d = func("deliver")
    assert "out === null" in d                           # Fehlerfall: nichts vorlesen
    assert "lastOut = " in d.split("}, () => {", 1)[0]   # nur echte Übersetzungen sind „repeat“-fähig
    assert "if (m.dst === pair.b)" in d                  # Partneransicht zeigt nur die Partnersprache
    assert "'mymemory'" in d                             # Ersatzdienst wird gekennzeichnet


def test_accessibility():
    assert re.search(r'id="announce"[^>]*aria-live="polite"', HTML)
    assert re.search(r'id="log"[^>]*aria-live="off"', HTML)   # sonst doppelte bzw. „…“-Ansagen
    assert "announce(out, m.dst)" in func("deliver")
    assert 'aria-labelledby="consentTitle"' in HTML
    assert '<html lang="de">' in HTML and 'name="viewport"' in HTML
    for m in re.finditer(r"<button\b[^>]*>(.*?)</button>", HTML, re.S):
        assert re.sub(r"<[^>]+>", "", m.group(1)).strip(), m.group(0)   # kein Knopf ohne Beschriftung
    for m in re.finditer(r'<input\b[^>]*id="(\w+)"', HTML):
        assert re.search(r"<label><input\b[^>]*id=\"" + m.group(1) + '"', HTML), m.group(1)
    assert "min-height:44px" in HTML                      # Fingertipp-Ziele auf dem Handy


def test_warnings_can_be_cleared():
    assert "function clearWarn" in SCRIPT and "r.onstart = () => clearWarn(" in SCRIPT


def test_status_line_is_quiet():
    assert re.search(r'id="status"[^>]*aria-live="off"', HTML)
    assert "announce(msg, UI)" in func("setStatus")


def test_hard_errors_and_no_recognition():
    assert "'audio-capture':" in SCRIPT.split("const HARD_ERR", 1)[1].split("};", 1)[0]
    no_sr = SCRIPT.split("if (!SR) {", 1)[1].split("}\n", 1)[0]
    assert "btn.disabled = true" in no_sr


def test_keys_blocked_behind_partner_and_not_after_checkbox():
    keys = SCRIPT.split("document.addEventListener('keydown'", 1)[1]
    assert keys.index("$('partner').classList.contains('on')) return;") < keys.index("KeyE")
    assert "checkbox|radio|range" in func("isTyping")


def test_tts_cancel_pause_and_settings_persist():
    sp = func("speakAsync")
    assert "TTS.cancel(); pre = wait(" in sp
    assert "localStorage.setItem('webSettings'" in func("saveSettings")
    for k in ("'dirA', 'dirB', 'speak', 'autoswitch', 'ptt'", "settings.rate", "settings.enVar", "settings.voices"):
        assert k in SCRIPT, k


def test_push_to_talk_keeps_last_sentence():
    end = func("pttEnd")
    assert "rec.stop()" in end and ".abort()" not in end   # abort() würde den letzten Satz verwerfen
    assert "if (pttReleased) { resumeIfIdle(); return; }" in func("scheduleRestart")
    assert "touch-action:none" in HTML and "contextmenu" in SCRIPT


def test_share_link_only_in_hash_and_never_autostarts():
    assert "'#show='" in func("shareUrl")
    ofh = func("openFromHash")
    assert "showBig(" in ofh and "speak" not in ofh.lower().replace("showbig", "") and "setMode" not in ofh
    assert "MAX_SHARE" in func("parseShare")


def test_viewport_safe_area_and_rtl():
    assert "viewport-fit=cover" in HTML and "env(safe-area-inset-bottom)" in HTML
    assert 'dir="auto"' in HTML
