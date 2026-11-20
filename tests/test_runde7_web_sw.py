"""Service Worker, Randfälle (node mit Attrappen): hängendes Netz, 206, fremde Pfade, Speicherfehler, Status."""
import json
import pathlib
import shutil
import subprocess

import pytest

SW = (pathlib.Path(__file__).resolve().parent.parent / "sw.js").read_text(encoding="utf-8")

HARNESS = r"""
const store = new Map(), handlers = {};
const resp = (body, status = 200) =>
  ({ ok: status >= 200 && status < 300, status, body, clone() { return resp(body, status); } });
let mode = 'online', putThrows = false;
const posted = [];
globalThis.self = {
  registration: { scope: 'https://example.org/app/' }, location: { origin: 'https://example.org' },
  addEventListener: (t, f) => { handlers[t] = f; }, skipWaiting: async () => {}, clients: { claim: async () => {} },
};
globalThis.fetch = async r => {
  const u = r.url || r;
  if (mode === 'offline') throw new Error('offline');
  if (mode === 'hang') return new Promise(() => {});
  if (u.endsWith('/partial.json')) return resp('part', 206);
  return resp('net:' + u);
};
const cache = {
  add: async u => { u = u.url || u; if (u.endsWith('icon-512.png')) throw new Error('404'); store.set(u, resp('net:' + u)); },
  put: async (r, v) => { if (putThrows) throw new Error('quota'); store.set(r.url || r, v); },
  match: async r => store.get(r.url || r),
};
globalThis.caches = { open: async () => cache, keys: async () => [], delete: async () => {},
  match: async u => store.get(u) };
function ev(type, request) {
  let waits = [], responded = null;
  handlers[type]({ request, waitUntil: p => waits.push(p), respondWith: p => { responded = p; } });
  if (type === 'fetch') return responded;   // Promise der Antwort (kann hängen)
  return Promise.all(waits.map(w => Promise.resolve(w).catch(() => {})));
}
(async () => {
  %SW%
  await ev('install');
  const out = {};
  // 1) Netz hängt, Kopie vorhanden: nach NAV_WAIT_MS kommt die gespeicherte App
  mode = 'hang';
  const t0 = Date.now();
  const nav = ev('fetch', { method: 'GET', url: 'https://example.org/app/', mode: 'navigate' });
  const r1 = await nav;
  out.hangBody = r1.body; out.hangMs = Date.now() - t0;
  // 2) Netz hängt, keine Kopie: es wird nicht blind etwas anderes gezeigt (Promise bleibt offen)
  store.delete('https://example.org/app/index.html'); store.delete('https://example.org/app/');
  let settled = false;
  const nav2 = { method: 'GET', url: 'https://example.org/app/', mode: 'navigate' };
  ev('fetch', nav2).then(() => { settled = true; }, () => { settled = true; });
  await new Promise(r => setTimeout(r, 4600));
  out.noCacheSettled = settled;
  // 3) 206 und fremde Pfade werden nicht gespeichert, Core-Datei schon
  mode = 'online';
  await ev('fetch', { method: 'GET', url: 'https://example.org/app/partial.json', mode: 'cors' });
  await ev('fetch', { method: 'GET', url: 'https://example.org/app/docs/x.md', mode: 'cors' });
  await ev('fetch', { method: 'GET', url: 'https://example.org/app/languages.json?v=2', mode: 'cors' });
  out.stored = [...store.keys()].filter(k => /partial|docs|languages/.test(k));
  // 4) put wirft: keine unbehandelte Ablehnung, Antwort kommt trotzdem
  putThrows = true;
  const r4 = await ev('fetch', { method: 'GET', url: 'https://example.org/app/languages.json', mode: 'cors' });
  out.putThrowsBody = r4.body;
  // 5) Status-Nachricht: 512er-Icon fehlt
  handlers.message({ data: { type: 'offline-status' }, source: { postMessage: m => posted.push(m) },
    waitUntil: p => p });
  await new Promise(r => setTimeout(r, 50));
  out.status = posted[0];
  process.stdout.write(JSON.stringify(out));
  process.exit(0);
})();
process.on('unhandledRejection', e => { console.error('unhandled', e); process.exit(2); });
"""


@pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")
def test_sw_edge_cases():
    r = subprocess.run(["node", "-"], input=HARNESS.replace("%SW%", SW), capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["hangBody"] == "net:https://example.org/app/index.html"   # gespeicherte Kopie, nicht das hängende Netz
    assert 3500 <= out["hangMs"] < 6000, out["hangMs"]
    assert out["noCacheSettled"] is False          # ohne Kopie weiter aufs Netz warten statt Leerseite
    assert out["stored"] == ["https://example.org/app/languages.json"]
    assert out["putThrowsBody"].startswith("net:https://example.org/app/languages.json")
    assert out["status"]["type"] == "offline-status" and out["status"]["total"] > out["status"]["ok"] >= 1


def test_cache_version_bumped_with_core_change():
    import re
    assert int(re.search(r"dolmetscher-web-v(\d+)", SW).group(1)) >= 7
