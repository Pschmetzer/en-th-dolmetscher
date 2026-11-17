"""Web Runde 5: Kulturhinweis und wichtige Sätze im Satzbuch, Lernmodus (Leitner), weitere Sprachbefehle,
Kopfhörer-Modus, Schriftgröße der Großansicht, sichtbarer Stopp. Reine Logik läuft in node (ohne node: übersprungen)."""
import json
import pathlib
import re
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SCRIPT = re.search(r"<script>(.*?)</script>", HTML, re.S).group(1)
SW = (ROOT / "sw.js").read_text(encoding="utf-8")
DAY = 86_400_000


def _func(name):
    one = re.search(r"^(?:async )?function " + name + r"\(.*\}$", SCRIPT, re.M)   # einzeilige Funktion
    if one and one.group(0).count("{") == one.group(0).count("}"):
        return one.group(0)
    m = re.search(r"^(?:async )?function " + name + r"\(.*?^\}", SCRIPT, re.S | re.M)
    assert m, name
    return m.group(0)


def _line(prefix):
    m = re.search(r"^" + re.escape(prefix) + r".*?;$", SCRIPT, re.S | re.M)
    assert m, prefix
    return m.group(0)


# --- statisch ---------------------------------------------------------------------------------------

def test_note_and_critical_rendering():
    rc = _func("renderCards")
    assert "presetNote(d)" in rc and "$('pbNote').textContent" in rc and "innerHTML" not in rc
    assert "criticalFirst(d.phrases)" in rc and "' crit'" in rc and "⚠ Wichtig" in rc   # nicht nur Farbe
    assert '<div id="pbNote" class="note" role="note" hidden></div>' in HTML
    assert "d.phrases.sort" not in SCRIPT                  # Preset-Objekt wird geteilt (presetCache): nie umsortieren


def test_no_nested_buttons_in_cards():
    rc = _func("renderCards")
    assert "className = 'cardwrap'" in rc and "w.append(c, starButton(" in rc and "box.appendChild(w)" in rc
    assert "c.appendChild(starButton" not in rc


def test_learn_storage_is_guarded():
    assert "localStorage.setItem(LEARN_KEY" in _func("learnStore")
    assert "try { localStorage.setItem(LEARN_KEY" in _func("learnStore")
    assert "try { return learnParse(localStorage.getItem(LEARN_KEY)); } catch { return []; }" in SCRIPT
    d = _func("deliver")
    ok_branch = d.split("}, () => {", 1)[0]
    assert "learnRecent" in ok_branch                      # nur echte Übersetzungen, nie Fehlertexte
    assert "learnRecent" not in d.split("}, () => {", 1)[1]
    assert ok_branch.index("announce(out, m.dst)") < ok_branch.index("learnItem(")   # Lernkarten nie vor der Ausgabe
    assert "Object.hasOwn(" not in SCRIPT                 # ältere Browser (Safari < 15.4)
    assert '<label><input type="checkbox" id="learnRecent">' in HTML   # Standard: aus
    assert "Lernkarten" in re.search(r'id="privacy">(.*?)</div>', HTML, re.S).group(1)
    assert "learnStore([])" in SCRIPT and "removeItem(LEARN_KEY)" in SCRIPT


def test_learn_ui_uses_textcontent():
    for n in ("learnRender", "starState", "learnReveal"):
        assert "innerHTML" not in _func(n), n
    assert "sayNow(learnCur.b.t, learnCur.b.l)" in SCRIPT    # vorgelesen wird die Partnersprache


def test_voice_commands_and_help():
    rc = _func("runCommand")
    for c in ("louder", "quieter", "clear", "help"):
        assert f"cmd === '{c}'" in rc, c
        assert f"„{c}“" in HTML, c
    assert "u.volume = vol" in _func("speakChunk")
    assert 'id="helpBox"' in HTML


def test_duplex_barge_in():
    assert "(speaking && !duplex())" in _func("startRec")
    assert "(speaking && !duplex())" in _func("scheduleRestart")
    sp = _func("speakAsync")
    assert "if (!duplex()) { stopRec();" in sp and "barge === b0" in sp
    assert "bargeIn()" in _func("startRec") and "TTS.cancel()" in _func("bargeIn")


def test_partner_font_scale_and_scroll():
    assert "overflow-y:auto" in HTML and "var(--pscale, 1)" in HTML
    assert 'id="btnFontDown"' in HTML and 'id="btnFontUp"' in HTML
    assert "settings.pscale" in _func("setScale")


def test_visible_stop_and_escape():
    assert '<button class="small" id="btnStop" type="button" disabled>' in HTML
    assert "$('btnStop').disabled = !mode" in _func("setMode")
    keys = SCRIPT.split("document.addEventListener('keydown'", 1)[1]
    esc = keys.split("if (!$('keysOn').checked)", 1)[0]
    assert "togglePartner(false)" in esc and "chooseMode(mode)" in esc and "setMode(" not in esc


def test_sw_cache_bumped():
    v = int(re.search(r"const CACHE = 'dolmetscher-web-v(\d+)'", SW).group(1))
    assert v >= 5


# --- Logik in node -----------------------------------------------------------------------------------

PRELUDE = "\n".join([
    _line("const LANGS ="), "let pair = { a: 'de', b: 'th' };", _line("const CMD_RE"),
    _line("const LEARN_KEY"), re.search(r"^const LEARN_DAYS.*$", SCRIPT, re.M).group(0),
    *(_func(n) for n in ("learnSide", "learnParse", "learnItem", "learnKey", "learnAdd", "learnRemove",
                         "leitnerNext", "learnDue", "criticalFirst", "presetNote", "parseCommand")),
])

CARD = {"a": {"t": "Hallo", "l": "de"}, "b": {"t": "สวัสดี", "l": "th"}}
CASES = [
    # Kulturhinweis: Sprache A, sonst de, sonst en; fehlend oder falscher Typ -> leer
    ("presetNote({note: {de: ' Hinweis ', en: 'Note'}})", "Hinweis"),
    ("pair = {a: 'en', b: 'th'}; const r = presetNote({note: {de: 'Hinweis', en: 'Note'}}); "
     "pair = {a: 'de', b: 'th'}; r", "Note"),
    ("presetNote({note: {en: 'Note'}})", "Note"),
    ("presetNote({})", ""),
    ("presetNote({note: 'x'})", ""),
    ("presetNote({note: {de: 5}})", ""),
    # wichtige Sätze zuerst, sonst stabile Reihenfolge, Original bleibt unverändert
    ("const l = [{en:'a'}, {en:'b', critical:true}, {en:'c'}, {en:'d', critical:true}]; "
     "[criticalFirst(l).map(p => p.en).join(''), l.map(p => p.en).join('')]", ["bdac", "abcd"]),
    ("criticalFirst(undefined)", []),
    # Karte: Vorderseite meine Sprache, Rückseite Partnersprache, egal wer gesprochen hat
    ("learnItem('Hallo', 'de', 'สวัสดี', 'th')", CARD),
    ("learnItem('สวัสดี', 'th', 'Hallo', 'de')", CARD),
    ("learnItem('', 'de', 'x', 'th')", None),
    ("learnItem('Hallo', 'de', 'Hallo', 'de')", None),
    ("learnItem('Hallo', 'xx', 'สวัสดี', 'th')", None),
    ("learnItem('a'.repeat(900), 'de', 'b', 'th').a.t.length", 500),
    # Leitner
    (f"leitnerNext({{...{json.dumps(CARD)}, box: 1, due: 0}}, true, 1000)", {**CARD, "box": 2, "due": 1000 + DAY}),
    (f"leitnerNext({{...{json.dumps(CARD)}, box: 4, due: 0}}, true, 0).due", 14 * DAY),
    (f"leitnerNext({{...{json.dumps(CARD)}, box: 5, due: 0}}, true, 0).box", 5),
    (f"leitnerNext({{...{json.dumps(CARD)}, box: 4, due: 0}}, false, 7)", {**CARD, "box": 1, "due": 7}),
    ("learnDue([{box: 2, due: 1, id: 'x'}, {box: 1, due: 5, id: 'y'}, {box: 1, due: 3, id: 'z'}, "
     "{box: 1, due: 99, id: 'later'}], 10).map(c => c.id)", ["z", "y", "x"]),
    # Hinzufügen: keine Doppelten, Merken setzt fav, voll -> ältester ungemerkter fliegt
    (f"const it = {json.dumps(CARD)}; const l1 = learnAdd([], it, 5, 'rec'); const l2 = learnAdd(l1, it, 6, 'fav'); "
     "[l1.length, l2.length, l2[0].fav, l2[0].rec, l2[0].due]", [1, 1, True, True, 5]),
    ("let l = learnAdd([], {a: {t: 'fav', l: 'de'}, b: {t: 'x', l: 'th'}}, 0, 'fav'); "
     "for (let i = 0; i < 205; i++) l = learnAdd(l, {a: {t: 'r' + i, l: 'de'}, b: {t: 'x', l: 'th'}}, i, 'rec'); "
     "[l.length, l[0].a.t, l[1].a.t]", [200, "fav", "r6"]),
    (f"learnRemove(learnAdd([], {json.dumps(CARD)}, 0, 'fav'), {json.dumps(CARD)})", []),
    # Laden: kaputte Daten werfen nie
    ("learnParse('{kaputt')", []),
    ("learnParse('{\"a\":1}')", []),
    ("learnParse(null)", []),
    ("learnParse(JSON.stringify([null, 5, {a: {t: 'x', l: 'de'}}, "
     "{a: {t: 'x', l: 'de'}, b: {t: 'y', l: '__proto__'}}]))", []),
    ("learnParse(JSON.stringify([{a: {t: 'x', l: 'de'}, b: {t: 'y', l: 'th'}, box: 9, due: 'x', fav: 'yes'}]))",
     [{"a": {"t": "x", "l": "de"}, "b": {"t": "y", "l": "th"}, "box": 1, "due": 0,
       "fav": False, "rec": False, "add": 0}]),
    # neue Sprachbefehle
    ("['louder', 'quieter', 'clear', 'help'].map(c => parseCommand('Translator ' + c))",
     ["louder", "quieter", "clear", "help"]),
    ("parseCommand('please help me')", None),
    ("parseCommand('clear the table translator')", None),
]


@pytest.fixture(scope="module")
def results():
    if not shutil.which("node"):
        pytest.skip("node nicht installiert")
    body = ",".join("(() => { try { return [true, (() => { " + _ret(e) + " })()]; } "
                    "catch (x) { return [false, String(x)]; } })()" for e, _ in CASES)
    r = subprocess.run(["node", "-e", PRELUDE + "\nprocess.stdout.write(JSON.stringify([" + body + "]));"],
                       capture_output=True, text=True, timeout=120)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def _ret(expr):   # mehrere Anweisungen: der letzte Ausdruck ist das Ergebnis
    head, _, last = expr.rpartition("; ")
    return (head + "; " if head else "") + "return " + last + ";"


@pytest.mark.parametrize("i", range(len(CASES)), ids=[c[0][:50] for c in CASES])
def test_js_logic(results, i):
    ok, value = results[i]
    assert ok, value
    assert value == CASES[i][1], CASES[i][0]
