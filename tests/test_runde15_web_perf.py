# ruff: noqa: E501
"""Runde 15 Web: Groessenbudget, kein Laden aller Pakete beim Start, Service Worker laedt Pakete nach dem Start,
Speicher voll (QuotaExceeded) wird gemeldet, begrenzte Parallelitaet."""
import json
import re
import shutil
import subprocess

import pytest

from _webhelpers import HAVE_NODE, HTML, ROOT, SCRIPT, func

SW = (ROOT / "sw.js").read_text(encoding="utf-8")
BUDGET_HTML = 215_000   # Runde 21b: 192 KB nach Auslagerung von en/th nach i18n/*.json (vorher 242 KB mit allen drei Sprachen)
BUDGET_I18N = 60_000     # je Datei i18n/<sprache>.json (th ist die grösste)
BUDGET_SW = 8_000
node = pytest.mark.skipif(not HAVE_NODE or not shutil.which("node"), reason="node nicht installiert")


def _node(src):
    r = subprocess.run(["node", "-"], input=src, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def test_i18n_files_within_budget():
    for lg in ("en", "th"):
        assert (ROOT / "i18n" / f"{lg}.json").stat().st_size <= BUDGET_I18N


def test_size_budget():
    assert len(HTML.encode("utf-8")) <= BUDGET_HTML
    assert len(SW.encode("utf-8")) <= BUDGET_SW


def test_start_loads_no_all_packs_synchronously():
    start = SCRIPT.split("function fillPresetSelect()", 1)[1].split("function renderEmerg", 1)[0]
    assert "PRESET_IDS.map" not in start and "loadPreset(" in start   # nur im Fehlerfall einzeln
    for m in re.finditer(r"PRESET_IDS\.map\(([^)]*)\)", SCRIPT):
        assert "loadPreset" not in m.group(0)
    assert "Promise.all(PRESET_IDS" not in SCRIPT      # Woerterbuch und Vorab-Uebersetzen: begrenzt parallel
    assert "mapLimit(PRESET_IDS, 6" in SCRIPT


def test_sw_install_caches_only_shell():
    inst = SW.split("addEventListener('install'", 1)[1].split("addEventListener('activate'", 1)[0]
    assert "CORE.map" in inst and "PACKS" not in inst.replace("keepOldPacks", "")
    assert "'cache-presets'" in SW and "FILL_PARALLEL" in SW


def test_page_asks_for_packs_after_start_not_on_data_saver():
    assert "type: 'cache-presets'" in HTML and "saveData" in HTML and "requestIdleCallback" in HTML


def test_texts_in_three_languages():
    from _webhelpers import web_str
    S = web_str()
    for lg in ("de", "en", "th"):
        for k in ("storageFull", "offlineLoading"):
            assert S[lg][k].strip(), (lg, k)


@node
def test_sw_install_shell_then_packs_on_message_and_old_packs_kept():
    out = _node(r"""
const store = new Map(), handlers = {}; const resp = b => ({ ok: true, status: 200, body: b, clone() { return resp(b); } });
const mk = () => new Map(); const caches_ = { 'dolmetscher-web-v1': mk(), [CUR]: mk() };
caches_['dolmetscher-web-v1'].set('https://x.test/a/presets/doctor.json', resp('old'));
let inflight = 0, maxIn = 0;
globalThis.self = { registration: { scope: 'https://x.test/a/' }, location: { origin: 'https://x.test' }, addEventListener: (t, f) => { handlers[t] = f; }, skipWaiting: async () => {}, clients: { claim: async () => {} } };
globalThis.fetch = async u => { inflight++; maxIn = Math.max(maxIn, inflight); await new Promise(r => setTimeout(r, 2)); inflight--; return resp('net:' + (u.url || u)); };
const open = async k => { const m = caches_[k]; return { add: async u => { u = u.url || u; m.set(u, resp('net:' + u)); }, put: async (u, v) => { m.set(u.url || u, v); }, match: async u => m.get(u.url || u) }; };
globalThis.caches = { open, keys: async () => Object.keys(caches_), delete: async () => {}, match: async () => undefined };
(async () => {
  %SW%
  const w = []; handlers.install({ waitUntil: p => w.push(p) }); await Promise.all(w);
  const n = caches_[CUR]; const out = {};
  out.afterInstall = [...n.keys()].filter(k => k.includes('/presets/') && !k.includes('index')).length;
  out.kept = n.get('https://x.test/a/presets/doctor.json').body;
  const posted = []; const w2 = [];
  handlers.message({ data: { type: 'cache-presets' }, source: { postMessage: m => posted.push(m) }, waitUntil: p => w2.push(p) }); await Promise.all(w2);
  out.afterFill = [...n.keys()].filter(k => /\/presets\/[a-z0-9-]+\.json$/.test(k)).length;
  out.total = PRESET_IDS.length; out.maxIn = maxIn; out.last = posted[posted.length - 1];
  process.stdout.write(JSON.stringify(out));
})();
""".replace("%SW%", SW).replace("[CUR]", "[" + repr(re.search(r"const CACHE = '([^']+)'", SW).group(1)) + "]").replace("caches_[CUR]", "caches_[" + repr(re.search(r"const CACHE = '([^']+)'", SW).group(1)) + "]"))
    assert out["afterInstall"] == 1 and out["kept"] == "old"      # nur das uebernommene alte Paket, nichts neu geladen
    assert out["afterFill"] == out["total"] and out["maxIn"] <= 4
    assert out["last"]["ok"] == out["last"]["total"] and out["last"]["loading"] is False


@node
def test_quota_exceeded_reported_once_and_pb_trims_oldest():
    m = re.search(r"^let storageNoteAt = 0;$", SCRIPT, re.M)
    assert m
    src = "\n".join([
        "const msgs = []; const setStatus = (m) => msgs.push(m); const t = k => k; let full = false, writes = 0;",
        "const localStorage = { setItem: () => { writes++; if (full) throw new DOMException('q', 'QuotaExceededError'); } };",
        m.group(0), re.search(r"^function storageFull\(\).*$", SCRIPT, re.M).group(0), re.search(r"^function lsSet\(.*$", SCRIPT, re.M).group(0),
        func("mapLimit"), "const PBT_MAX = 100; const pbTrans = {};", func("pbSave"),
        r"""(async () => {
  const o = {}; full = true;
  o.r1 = lsSet('a', '1'); o.r2 = lsSet('a', '1'); o.msgs = msgs.length;   // zweimal voll: eine Meldung
  for (let i = 0; i < 40; i++) pbTrans['k' + i] = { t: 'x', ts: i };
  writes = 0; pbSave(); o.left = Object.keys(pbTrans).length; o.writes = writes;      // dauerhaft voll: bricht nach 4 Versuchen ab
  full = false; writes = 0; pbTrans.z = { t: 'y', ts: 99 }; pbSave(); o.okWrites = writes;
  let cur = 0, peak = 0;
  const res = await mapLimit([1, 2, 3, 4, 5, 6, 7, 8, 9], 3, async x => { cur++; peak = Math.max(peak, cur); await new Promise(r => setTimeout(r, 3)); cur--; return x * 2; });
  o.peak = peak; o.res = res;
  process.stdout.write(JSON.stringify(o));
})();"""])
    o = _node(src)
    assert o["r1"] is False and o["r2"] is False and o["msgs"] == 1
    assert o["writes"] == 4 and o["left"] < 40              # vier Versuche, dazwischen je ein Viertel weg
    assert o["okWrites"] == 1
    assert o["peak"] == 3 and o["res"] == [2, 4, 6, 8, 10, 12, 14, 16, 18]
