# ruff: noqa: E501
"""Gemeinsame Hilfen fuer Web-Tests: Funktionen aus index.html herausloesen und in node ausfuehren."""
import json
import pathlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SCRIPT = re.search(r"<script>(.*?)</script>", HTML, re.S).group(1)
HAVE_NODE = bool(shutil.which("node"))


def func(name):
    m = re.search(r"^(?:async )?function " + name + r"\(.*?^\}", SCRIPT, re.S | re.M)
    assert m, name
    return m.group(0)


def line(prefix):
    m = re.search(r"^" + re.escape(prefix) + r".*?;$", SCRIPT, re.S | re.M)
    assert m, prefix
    return m.group(0)


def prelude(funcs=(), lines=()):
    lang = (ROOT / "languages.json").read_text(encoding="utf-8")
    parts = ["const SCRIPTS = {}, LANGS = {};", line("const hexRange"), line("const SCRIPT_RX ="), func("buildScriptRx"),
             func("applyLangTable"), f"applyLangTable({lang});", "let pair = { a: 'de', b: 'th' };"]
    parts += [line(x) for x in lines] + [func(x) for x in funcs]
    return "\n".join(parts)


def run(pre, exprs):
    """Wertet Ausdruecke (Strings) nach dem Vorspann aus; Ergebnis: Liste der JSON-Werte."""
    body = ",".join("(() => { try { return " + e + "; } catch (x) { return 'ERR ' + x; } })()" for e in exprs)
    r = subprocess.run(["node", "-"], input=pre + "\nprocess.stdout.write(JSON.stringify([" + body + "]));",
                       capture_output=True, text=True, timeout=120)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def web_str():
    """Oberflächentexte {de, en, th}: Deutsch steckt in index.html (STR), en/th in i18n/*.json (seit Runde 21)."""
    m = re.search(r"^const STR = (\{.*?^\});", SCRIPT, re.S | re.M)
    out = json.loads(m.group(1))
    for lg in ("en", "th"):
        out[lg] = json.loads((ROOT / "i18n" / f"{lg}.json").read_text(encoding="utf-8"))
    return {k: out[k] for k in ("de", "en", "th")}
