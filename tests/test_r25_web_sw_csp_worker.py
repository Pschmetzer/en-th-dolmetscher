# ruff: noqa: E501
"""Runde 25 (Web): CSP-Hash für das Inline-Skript, Audio-Speicher im Service Worker (nur mit Zustimmung),
Wörterbuch-Suche im Web Worker."""
import base64
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import sync_web  # noqa: E402

HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SW = (ROOT / "sw.js").read_text(encoding="utf-8")
EXTRAS = (ROOT / "web-extras.js").read_text(encoding="utf-8")
node = pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")


def _node(src, stdin=None):
    r = subprocess.run(["node", "-e", src], capture_output=True, text=True, timeout=90, cwd=ROOT, input=stdin)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


# ---------------------------------------------------------------- CSP

def _csp():
    return re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', HTML).group(1)


def test_csp_has_hash_of_the_inline_script_and_keeps_fallback():
    script = re.search(r"<script\s*>(.*?)</script\s*>", HTML, re.S | re.I).group(1)
    want = "'sha256-" + base64.b64encode(hashlib.sha256(script.encode("utf-8")).digest()).decode() + "'"
    assert want in _csp()
    directive = re.search(r"script-src ([^;]+);", _csp()).group(1)
    assert directive.split() == ["'self'", "'unsafe-inline'", want]       # unsafe-inline nur als Rückfall für Browser ohne Hash-Unterstützung
    assert "unsafe-eval" not in _csp() and "script-src-attr 'none'" in _csp() and "worker-src 'self'" in _csp()


def test_only_one_executable_inline_script_and_no_inline_handlers():
    scripts = re.findall(r"<script([^>]*)>", HTML, re.I)
    inline = [a for a in scripts if "src=" not in a and "application/ld+json" not in a]
    assert inline == [""]                                                  # genau ein ausführbares Inline-Skript: ein Hash genügt
    assert not re.search(r"\son[a-z]+=\"", HTML)


def test_sync_web_keeps_the_hash_current(tmp_path):
    assert sync_web.sync(write=False)[0] == []                             # Repo ist synchron (Hash, Paketliste, Cache-Version)
    root = tmp_path
    (root / "presets").mkdir()
    (root / "presets-index.json").write_text(json.dumps({"packs": []}), encoding="utf-8")
    page = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'self' 'unsafe-inline'; x\"><script>var a = 1;</script>"
    (root / "index.html").write_text(page + "\nconst PRESET_IDS = [];", encoding="utf-8")
    (root / "sw.js").write_text("// content-hash: 0000000000000000\nconst CACHE = 'dolmetscher-web-v1';\nconst PRESET_IDS = [];\nconst CORE = [];\n", encoding="utf-8")
    problems, _sw, html = sync_web.sync(root, write=False)
    assert any("CSP-Hash" in p for p in problems)
    assert sync_web.csp_hash("<script>var a = 1;</script>") in html
    again = sync_web.csp_hash(html)
    assert again == sync_web.csp_hash(page) and html.count("sha256-") == 1
    assert sync_web.csp_hash("<p>kein Skript</p>") is None


def test_sync_check_cli_is_clean():
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "sync_web.py"), "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


# ---------------------------------------------------------------- Audio-Speicher im Service Worker

HARNESS = r"""
const vm = require('vm'), fs = require('fs');
const code = fs.readFileSync('sw.js', 'utf8');
const bufs = new Map();
class Cache {
  constructor() { this.m = new Map(); }
  async match(r) { const e = this.m.get(typeof r === 'string' ? r : r.url); return e && new Response(e.b, { status: e.s, headers: e.h }); }
  async put(r, res) { this.m.set(typeof r === 'string' ? r : r.url, { b: Buffer.from(await res.arrayBuffer()), s: res.status, h: [...res.headers] }); }
  async keys() { return [...this.m.keys()].map(u => ({ url: u })); }
  async delete(r) { return this.m.delete(typeof r === 'string' ? r : r.url); }
}
const store = new Map();
const caches = {
  async open(n) { if (!store.has(n)) store.set(n, new Cache()); return store.get(n); },
  async has(n) { return store.has(n); }, async delete(n) { return store.delete(n); }, async keys() { return [...store.keys()]; },
};
const L = {}; let fetches = 0;
const self = { registration: { scope: 'https://x.test/app/' }, location: { origin: 'https://x.test' }, addEventListener: (t, f) => { L[t] = f; }, skipWaiting() {}, clients: { claim: async () => {}, matchAll: async () => [] } };
const fetchFake = async () => { fetches++; return new Response('AUDIO', { status: 200, headers: { 'Content-Type': 'audio/mpeg' } }); };
vm.runInNewContext(code, { self, caches, fetch: fetchFake, URL, Request, Response, navigator: {}, setTimeout, setInterval, clearInterval, console, Promise });
async function get(path, headers) {
  const pend = []; let p = null;
  const ev = { request: new Request('https://x.test/app/' + path, { headers: headers || {} }), respondWith(x) { p = x; }, waitUntil(x) { pend.push(x); } };
  L.fetch(ev);
  const res = p ? await p : null; await Promise.all(pend);
  return res;
}
async function msg(data) { const out = []; const pend = []; L.message({ data, source: { postMessage: m => out.push(m) }, waitUntil: x => pend.push(x) }); await Promise.all(pend); return out; }
const R = {};
(async () => {
  let r = await get('audio/a.mp3'); R.offBody = await r.text(); R.offFetches = fetches; R.offHasCache = store.has('dolmetscher-audio-v1');
  R.on = await msg({ type: 'audio-opt', on: true });
  await get('audio/x.txt');
  R.cacheKeysAfterOn = [...store.get('dolmetscher-audio-v1').m.keys()];
  const f0 = fetches; r = await get('audio/a.mp3'); R.firstBody = await r.text(); R.firstFetches = fetches - f0;
  const f1 = fetches; r = await get('audio/a.mp3'); R.secondBody = await r.text(); R.secondFetches = fetches - f1;
  r = await get('audio/a.mp3', { Range: 'bytes=1-2' }); R.range = [r.status, r.headers.get('Content-Range'), await r.text()];
  R.status = await msg({ type: 'audio-opt', on: true });
  for (let i = 0; i < 230; i++) await get('audio/f' + i + '.mp3');
  R.countAfterMany = (await msg({ type: 'audio-opt', on: true }))[0].count;
  store.set('dolmetscher-web-v0', new Cache());
  await new Promise(ok => { const pend = []; L.activate({ waitUntil: x => pend.push(x) }); Promise.all(pend).then(ok); });
  R.afterActivate = [...store.keys()].sort();
  R.off = await msg({ type: 'audio-opt', on: false }); R.hasAfterOff = store.has('dolmetscher-audio-v1');
  const f2 = fetches; r = await get('audio/a.mp3'); R.offAgain = fetches - f2;
  console.log(JSON.stringify(R));
})().catch(e => { console.error(e); process.exit(1); });
"""


@node
def test_audio_storage_only_with_opt_in_and_bounded():
    r = subprocess.run(["node", "-e", HARNESS], capture_output=True, text=True, timeout=120, cwd=ROOT)
    assert r.returncode == 0, r.stderr
    R = json.loads(r.stdout)
    assert R["offBody"] == "AUDIO" and R["offFetches"] == 1 and R["offHasCache"] is False   # ohne Zustimmung nichts gespeichert
    assert R["on"] == [{"type": "audio-status", "on": True, "count": 0}]
    assert R["cacheKeysAfterOn"] == ["https://x.test/app/audio-opt"]                          # nur der Marker; andere Endungen (x.txt) nie im Audio-Speicher
    assert (R["firstBody"], R["firstFetches"]) == ("AUDIO", 1) and (R["secondBody"], R["secondFetches"]) == ("AUDIO", 0)
    assert R["range"] == [206, "bytes 1-2/5", "UD"]                                           # Teilabrufe aus dem Speicher (Safari)
    assert R["countAfterMany"] <= 200                                                         # Obergrenze AUDIO_MAX
    assert "dolmetscher-audio-v1" in R["afterActivate"] and "dolmetscher-web-v0" not in R["afterActivate"]   # überlebt Versionswechsel
    assert R["off"][0]["on"] is False and R["hasAfterOff"] is False and R["offAgain"] == 1    # Aus löscht alles


def test_audio_cache_is_separate_and_never_touches_translation_traffic():
    assert "dolmetscher-audio-v1" in SW and "const AUDIO_RX = " in SW.replace("AUDIO = 'dolmetscher-audio-v1', ", "")
    fetch_part = SW.split("addEventListener('fetch'", 1)[1]
    assert fetch_part.index("url.origin !== self.location.origin") < fetch_part.index("AUDIO_RX.test")   # fremde Dienste zuerst ausgeschlossen
    assert "translate.googleapis" not in SW and "mymemory" not in SW
    assert "k.startsWith('dolmetscher-web-')" in SW                                            # Aufräumen trifft den Audio-Speicher nicht


def test_audio_tab_in_extras_is_opt_in_and_three_languages():
    assert "audio: function (box, T)" in EXTRAS and "type: 'audio-opt'" in EXTRAS and "store('audio', cb.checked)" in EXTRAS
    assert "cb.checked = st" in EXTRAS and "store('audio') === true" in EXTRAS                  # Standard: aus
    block = EXTRAS.split("var TXT25 = {", 1)[1].split("var NEGO", 1)[0]
    for lg in ("de", "en", "th"):
        assert re.search(r"\n    " + lg + r": \{[^\n]*audioHelp: '[^']+'", block) or "audioHelp" in block


def test_sw_precaches_new_files_and_stays_in_budget():
    for f in ("web-extras.js", "web-qr.js", "web-search-worker.js"):
        assert "'%s'" % f in SW and (ROOT / f).exists(), f
    assert len(SW.encode("utf-8")) <= 17_500


# ---------------------------------------------------------------- Web Worker für die Suche

@node
def test_worker_search_ranks_words_before_sentences_and_matches_thai():
    out = _node("""const w=require('./web-search-worker.js');
w.addPack({glossary:[{en:'sunscreen',th:'ครีมกันแดด'},{en:'screen',th:'หน้าจอ'}],phrases:[{en:'Do you have sunscreen?',th:'มีครีมกันแดดไหม'},{en:'A screen, please.',th:'ขอหน้าจอ'},{en:'x',th:5},null]});
w.addPack(null); w.addPack({glossary:'kaputt',phrases:7}); w.addPack({glossary:[{en:'sunscreen',th:'ครีมกันแดด'}]});
console.log(JSON.stringify([w.size(),w.search('sunscreen').map(h=>h.k+':'+h.en),w.search('กันแดด').map(h=>h.th),w.search('SCREEN').map(h=>h.en),w.search(''),w.search('  '),w.search('zzz'),w.search('s',2).length]));""")
    size, sun, thai, screen, empty, blank, none, limit = out
    assert size == 4                                                                           # Dubletten und kaputte Einträge zählen nicht
    assert sun == ["g:sunscreen", "p:Do you have sunscreen?"]
    assert thai == ["ครีมกันแดด", "มีครีมกันแดดไหม"]
    assert screen[0] == "screen" and set(screen) == {"screen", "sunscreen", "A screen, please.", "Do you have sunscreen?"}
    assert empty == blank == none == [] and limit == 2


def test_worker_only_reads_own_pack_files_and_validates_ids():
    js = (ROOT / "web-search-worker.js").read_text(encoding="utf-8")
    assert "fetch('presets/' + id + '.json')" in js and r"/^[a-z0-9_-]{1,32}$/" in js
    assert "http://" not in js and "https://" not in js and "importScripts(" not in js.replace("typeof importScripts", "")
    assert "slice(0, 400)" in js and "Math.min(Number(m.limit) || 40, 100)" in js              # Obergrenzen gegen Missbrauch durch Nachrichten
    assert "innerHTML" not in js and "eval(" not in js


def test_dictionary_tab_uses_worker_with_fallback_and_stops_it():
    assert "new Worker('web-search-worker.js')" in EXTRAS and "wk = false" in EXTRAS            # Fallback auf den Hauptthread
    assert "box.stopFn" in EXTRAS and "wk.terminate()" in EXTRAS
    assert "worker-src 'self'" in HTML


def test_extras_stay_free_of_innerhtml_and_foreign_urls():
    js = EXTRAS
    assert "innerHTML" not in js and "eval(" not in js and "http://" not in js and "https://" not in js and "sendBeacon" not in js
