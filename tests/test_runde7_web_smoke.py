# ruff: noqa: E501
"""Rauchtest: das Skript von index.html laeuft in node mit Attrappen ohne Fehler an (Start, Spracherkennung fehlt, kein Netz)."""
import pathlib
import re
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SCRIPT = re.search(r"<script>(.*?)</script>", HTML, re.S).group(1)

HARNESS = r"""
const store = {}; const els = {};
const TEXT = new Set(['value', 'textContent', 'innerHTML', 'lang', 'className', 'href', 'id', 'dir']);
const FLAG = new Set(['checked', 'hidden', 'disabled', 'open', 'inert']);
function el(id) {
  const t = {};
  return new Proxy(function () {}, {
    get(_, k) {
      if (k in t) return t[k];
      if (k === 'classList') return { add() {}, remove() {}, toggle() {}, contains() { return false; } };
      if (k === 'style' || k === 'dataset') return t[k] = { setProperty() {} };
      if (k === 'options' || k === 'children') return [];
      if (k === 'files') return [];
      if (k === Symbol.toPrimitive) return () => '';
      if (k === 'then') return undefined;
      if (TEXT.has(k)) return '';
      if (FLAG.has(k)) return false;
      if (k === 'firstElementChild') return null;
      return () => el();
    },
    set(_, k, v) { t[k] = v; return true; },
    apply() { return el(); },
  });
}
globalThis.window = globalThis; globalThis.addEventListener = () => {};
globalThis.document = {
  getElementById: id => els[id] || (els[id] = el(id)), createElement: () => el(), querySelector: () => el(), querySelectorAll: () => [],
  addEventListener() {}, body: el(), hidden: false, activeElement: el(),
};
Object.defineProperty(globalThis, 'navigator', { value: { onLine: true, userAgent: 'node', language: 'de', clipboard: { writeText: async () => {} } }, configurable: true });
globalThis.localStorage = { getItem: k => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; } };
globalThis.location = { hash: '', search: '', pathname: '/', origin: 'http://x', protocol: 'http:' };
globalThis.history = { pushState() {}, replaceState() {}, state: null, back() {} };
globalThis.matchMedia = () => ({ matches: false });
globalThis.fetch = () => Promise.reject(new Error('kein Netz'));
globalThis.setInterval = () => 0;
globalThis.isSecureContext = false;
const timers = []; globalThis.setTimeout = (f, ms) => { timers.push(f); return timers.length; }; globalThis.clearTimeout = () => {};
const errors = [];
process.on('unhandledRejection', e => errors.push('unhandled: ' + (e && e.stack || e)));
process.on('uncaughtException', e => errors.push('uncaught: ' + (e && e.stack || e)));
try {
  (0, eval)(%SCRIPT%);
} catch (e) { errors.push('load: ' + (e && e.stack || e)); }
setImmediate(() => setImmediate(() => { process.stdout.write(JSON.stringify(errors)); process.exit(0); }));
"""


@pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")
def test_script_loads_and_starts_without_errors():
    import json
    code = HARNESS.replace("%SCRIPT%", json.dumps(SCRIPT))
    r = subprocess.run(["node", "-e", code], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout) == []
