// Service Worker der Web-Version: macht die Seite installierbar und das Satzbuch offline nutzbar.
// Nur eigene Dateien (gleicher Ursprung, GET). Übersetzungs-Anfragen (Google, MyMemory) laufen nie hier durch
// und werden nie gespeichert. Neue Version: CACHE hochzählen.
const CACHE = 'dolmetscher-web-v13';
const PRESET_IDS = ['doctor', 'police', 'lostchild', 'pharmacy', 'dentist', 'taxi', 'places', 'airport', 'transport', 'travel', 'hotel', 'restaurant', 'shopping', 'bank', 'answers', 'access', 'spa', 'temple', 'island', 'scooter', 'rental', 'services', 'coworking', 'office', 'baby', 'beach', 'bus-train', 'car-rental', 'diving', 'emergency', 'festival', 'gym', 'hiking', 'hospital', 'kids', 'laundry-repair', 'market', 'massage', 'mobile-sim', 'monk', 'nightlife', 'nomad', 'pets', 'pharmacy-otc', 'photo', 'school', 'sport', 'street-food', 'visa', 'wedding', 'work'];
const CORE = ['./', 'index.html', 'languages.json', 'presets-index.json', 'allergens.json', 'manifest.webmanifest', 'icon.svg', 'icon-192.png', 'icon-512.png']
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

const NAV_WAIT_MS = 4000;   // hängendes Netz: nach 4 s die gespeicherte Seite zeigen (falls vorhanden)
const corePaths = new Set(CORE.map(u => new URL(abs(u)).pathname));
const cacheable = url => corePaths.has(url.pathname);   // nur eigene Vorab-Dateien (inkl. presets/), nie fremde Pfade
const cachedApp = () => caches.match(abs('index.html')).then(r => r || caches.match(abs('./')));

// Seite fragt, wie viele Vorab-Dateien offline bereit sind (Anzeige "Offline bereit")
self.addEventListener('message', e => {
  if (!e.data || e.data.type !== 'offline-status' || !e.source) return;
  e.waitUntil(caches.open(CACHE).then(c => Promise.all(CORE.map(u => c.match(abs(u)))))
    .then(hits => e.source.postMessage({ type: 'offline-status', ok: hits.filter(Boolean).length, total: CORE.length })));
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;   // fremde Dienste: Browser direkt, nichts speichern
  if (req.mode === 'navigate') {                     // Seite: zuerst Netz (Updates), offline aus dem Speicher
    // Nur die App selbst als index.html merken – nicht direkt geöffnete Presets, Doku oder sw.js.
    const isApp = url.pathname === new URL(abs('./')).pathname || url.pathname === new URL(abs('index.html')).pathname;
    const net = fetch(req).then(r => {
      if (r.ok && r.status === 200 && isApp) {
        const copy = r.clone();
        caches.open(CACHE).then(c => c.put(abs('index.html'), copy)).catch(() => {});
      }
      return r;
    });
    if (!isApp) { e.respondWith(net.catch(() => cachedApp().then(r => r || Promise.reject(new Error('offline'))))); return; }
    // Netz kommt nicht binnen NAV_WAIT_MS (Roaming, Anmeldeseite im WLAN): gespeicherte App zeigen, Netz läuft im Hintergrund weiter
    e.waitUntil(net.catch(() => {}));
    e.respondWith(new Promise((resolve, reject) => {
      let done = false;
      const finish = (fn, v) => { if (!done) { done = true; clearTimeout(timer); fn(v); } };
      const timer = setTimeout(() => { cachedApp().then(r => { if (r) finish(resolve, r); }, () => {}); }, NAV_WAIT_MS);
      net.then(r => finish(resolve, r), err => cachedApp().then(r => r ? finish(resolve, r) : finish(reject, err), () => finish(reject, err)));
    }));
    return;
  }
  // Sprachtabelle, Presets, Icons, Manifest: sofort aus dem Speicher, im Hintergrund auffrischen
  e.respondWith(caches.open(CACHE).then(c => c.match(req, { ignoreSearch: true }).then(hit => {
    const net = fetch(req).then(r => {
      // nur vollständige Antworten (200, nicht 206) und nur bekannte Dateien speichern; Fehler beim Speichern ignorieren
      if (r.ok && r.status === 200 && cacheable(url)) c.put(url.origin + url.pathname, r.clone()).catch(() => {});   // ohne ?query: kein Wachstum durch Varianten
      return r;
    });
    if (hit) { e.waitUntil(net.catch(() => {})); return hit; }
    return net;
  })));
});
