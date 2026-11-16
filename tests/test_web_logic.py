"""Reine Logik der Web-Version mit node ausführen: Funktionen aus index.html herauslösen und prüfen
(splitText, parseCommand, Schrift-Plausibilität, Link-Teilen). Ohne node: übersprungen."""
import json
import pathlib
import re
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SCRIPT = re.search(r"<script>(.*?)</script>", HTML, re.S).group(1)

pytestmark = pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")


def _func(name):
    m = re.search(r"^(?:async )?function " + name + r"\(.*?^\}", SCRIPT, re.S | re.M)
    assert m, name
    return m.group(0)


def _line(prefix):
    m = re.search(r"^" + re.escape(prefix) + r".*?;$", SCRIPT, re.S | re.M)
    assert m, prefix
    return m.group(0)


PRELUDE = "\n".join([
    _line("const SCRIPTS ="), _line("const LANGS ="), _line("const MAX_SOFT_ERR"),
    re.search(r"^const SCRIPT_RX = .*?^\}", SCRIPT, re.S | re.M).group(0),
    _line("const isLatin"), _line("const CMD_RE"),
    *(_func(n) for n in ("scriptsDistinct", "scriptShare", "untranslated", "wrongScript", "implausible",
                         "textLang", "splitText", "parseCommand", "parseShare")),
])



LONG = "Hello there. " * 40
IMG = "<img src=x onerror=alert(1)>"
# (JS-Ausdruck, erwartetes Ergebnis) – alle in EINEM node-Lauf ausgewertet (node startet langsam)
CASES = [
    # splitText
    ("splitText('a'.repeat(400), 180).map(p => p.length)", [180, 180, 40]),
    ("splitText('', 300)", []),
    ("splitText('你好。今天天气很好。'.repeat(30), 50).length > 1", True),            # CJK-Satzzeichen
    (f"splitText({json.dumps(LONG)}, 180).every(p => p.length <= 180)", True),
    (f"splitText({json.dumps(LONG)}, 180).join(' ').split(/\\s+/).join(' ')", LONG.strip()),
    # parseCommand
    ("parseCommand('Translator pause')", "pause"),
    ("parseCommand(\"hey translator's, slower!\")", "slower"),
    ("parseCommand('please translate pause the video')", None),
    ("parseCommand('The translator was slow')", None),
    # Schrift-Tabelle
    ("[scriptsDistinct('en','th'), scriptsDistinct('de','es'), scriptsDistinct('zh','ja'), "
     "scriptsDistinct('ru','uk'), scriptsDistinct('en','xx')]", [True, False, False, False, False]),
    ("scriptShare('สวัสดี', 'th')", 1),
    ("scriptShare('123 !', 'th')", 0),
    ("scriptShare('Hi สวัส', 'th') > 0.4 && scriptShare('Hi สวัส', 'th') < 0.8", True),
    # wie dolmetscher._untranslated / _wrong_script
    ("untranslated('Hello there', 'Hello there', 'en', 'th')", True),
    ("untranslated('Hello there', 'สวัสดี', 'en', 'th')", False),
    ("untranslated('OK', 'OK', 'en', 'th')", False),                                  # zu kurz für eine Aussage
    ("untranslated('สวัสดีครับ', 'สวัสดีครับ', 'th', 'en')", False),                    # lateinisches Ziel: wrongScript
    ("wrongScript('สวัสดีครับ', 'th', 'en')", True),
    ("wrongScript('Hello Bangkok สนามบิน', 'th', 'en')", False),
    ("implausible('Hola amigo', 'Hola amigo', 'es', 'de')", False),                   # gleiche Schrift: keine Prüfung
    ("implausible('Hello world', 'Привет мир', 'en', 'ru')", False),
    # wie dolmetscher.text_lang
    ("textLang('สวัสดีครับ', 'en', 'en', 'th')", "th"),
    ("textLang('hello my friend', 'th', 'en', 'th')", "en"),
    ("textLang('hello', 'de', 'de', 'es')", "de"),
    ("textLang('123', 'th', 'en', 'th')", "th"),
    ("textLang('こんにちは', 'en', 'en', 'ja')", "ja"),
    # Link-Teilen
    ("parseShare('#show=' + encodeURIComponent('ไปสนามบิน') + '&l=th')", {"text": "ไปสนามบิน", "lang": "th"}),
    ("parseShare('#show=hi&l=xx')", None),                                            # unbekannte Sprache
    ("parseShare('#show=&l=th')", None),
    ("parseShare('')", None),
    ("parseShare('#show=' + 'a'.repeat(2000) + '&l=en').text.length", 500),
    (f"parseShare('#show=' + encodeURIComponent({json.dumps(IMG)}) + '&l=en').text", IMG),   # bleibt Text
]


@pytest.fixture(scope="module")
def results():
    body = ",".join("(() => { try { return [true, " + e + "]; } catch (x) { return [false, String(x)]; } })()"
                    for e, _ in CASES)
    r = subprocess.run(["node", "-e", PRELUDE + "\nprocess.stdout.write(JSON.stringify([" + body + "]));"],
                       capture_output=True, text=True, timeout=120)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


@pytest.mark.parametrize("i", range(len(CASES)), ids=[c[0][:50] for c in CASES])
def test_js_logic(results, i):
    ok, value = results[i]
    assert ok, value
    assert value == CASES[i][1], CASES[i][0]


def test_share_view_renders_text_only():
    show_big = re.search(r"^function showBig\(.*$", SCRIPT, re.M).group(0)
    assert "innerHTML" not in show_big + _func("setPartnerText") + _func("openFromHash")
