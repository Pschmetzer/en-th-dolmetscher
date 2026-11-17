// Service Worker der Web-Version: macht die Seite installierbar und das Satzbuch offline nutzbar.
// Nur eigene Dateien (gleicher Ursprung, GET). Übersetzungs-Anfragen (Google, MyMemory) laufen nie hier durch
// und werden nie gespeichert. Neue Version: CACHE hochzählen.
const CACHE = 'dolmetscher-web-v5';
const PRESET_IDS = ['taxi', 'hotel', 'restaurant', 'shopping', 'travel', 'doctor', 'office', 'pharmacy', 'police', 'bank', 'spa', 'temple', 'rental', 'scooter', 'transport', 'lostchild'];
const CORE = ['./', 'index.html', 'manifest.webmanifest', 'icon.svg', 'icon-192.png', 'icon-512.png']
  .concat(PRESET_IDS.map(id => 'presets/' + id + '.json'));
const abs = u => new URL(u, self.registration.scope).href;   // GitHub Pages liegt unter /en-th-dolmetscher/

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE)
    .then(c => Promise.all(CORE.map(u => c.add(abs(u)).catch(() => {}))))   // eine fehlende Datei bricht nichts ab
    .then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k.startsWith('dolmetscher-web-') && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;   // fremde Dienste: Browser direkt, nichts speichern
  if (req.mode === 'navigate') {                     // Seite: zuerst Netz (Updates), offline aus dem Speicher
    // Nur die App selbst als index.html merken – nicht direkt geöffnete Presets, Doku oder sw.js.
    const isApp = url.pathname === new URL(abs('./')).pathname || url.pathname === new URL(abs('index.html')).pathname;
    e.respondWith(fetch(req).then(r => {
      if (r.ok && isApp) { const copy = r.clone(); caches.open(CACHE).then(c => c.put(abs('index.html'), copy)); }
      return r;
    }).catch(() => caches.match(abs('index.html')).then(r => r || caches.match(abs('./')))));
    return;
  }
  // Presets, Icons, Manifest: sofort aus dem Speicher, im Hintergrund auffrischen
  e.respondWith(caches.open(CACHE).then(c => c.match(req, { ignoreSearch: true }).then(hit => {
    const net = fetch(req).then(r => { if (r.ok) c.put(req, r.clone()); return r; });
    if (hit) { e.waitUntil(net.catch(() => {})); return hit; }
    return net;
  })));
});
