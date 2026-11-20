// Service Worker der Web-Version: macht die Seite installierbar und das Satzbuch offline nutzbar.
// Nur eigene Dateien (gleicher Ursprung, GET). Übersetzungs-Anfragen (Google, MyMemory) laufen nie hier durch
// und werden nie gespeichert. Neue Version: CACHE hochzählen (nötig bei neuen Dateien; index.html wird ohnehin zuerst vom Netz geholt).
const CACHE = 'dolmetscher-web-v24';
const PRESET_IDS = ['doctor', 'police', 'lostchild', 'pharmacy', 'dentist', 'taxi', 'places', 'airport', 'transport', 'travel', 'hotel', 'restaurant', 'shopping', 'bank', 'answers', 'access', 'spa', 'temple', 'island', 'scooter', 'rental', 'services', 'coworking', 'office', 'adventure-park', 'animal-bite-rabies', 'atm-bank-card', 'baby', 'babysitter-housekeeper', 'badminton-tennis', 'bakery-cafe', 'bangkok-skytrain', 'beach', 'bicycle-rental', 'birthday-celebration', 'border-crossing', 'buddhist-ceremony', 'buffet-bbq', 'bus-train', 'cannabis-vape', 'car-accident', 'car-rental', 'car-wash-repair', 'chronic-conditions', 'cinema-concert', 'convenience-store-7eleven', 'currency-exchange', 'customs-duty-free', 'dating-small-talk', 'diving', 'earthquake-evacuation', 'elephant-sanctuary', 'emergency', 'ferry-boat', 'festival', 'fishing-trip', 'flight-delay-change', 'floating-market', 'food-allergy', 'food-delivery', 'funeral-condolence', 'gas-station-parking', 'golf', 'grab-ride-hailing', 'gym', 'hair-beauty', 'heat-health', 'hiking', 'home-repair', 'hospital', 'hostel-dorm', 'immigration-90day', 'island-hopping', 'jet-ski-rental', 'karaoke', 'kayak-national-park', 'kids', 'kids-playground', 'laundry-deposit', 'laundry-repair', 'lost-luggage', 'lost-passport', 'lost-phone', 'market', 'massage', 'mental-health-counseling', 'mobile-sim', 'monk', 'monsoon-flood-storm', 'mosque-visit', 'mosquito-dengue', 'motorbike-accident', 'motorcycle-taxi', 'muay-thai-gym', 'night-market-bargain', 'nightlife', 'nomad', 'optician-eye-care', 'pets', 'pharmacy-otc', 'photo', 'physiotherapy-injury', 'police-checkpoint', 'post-office-parcel', 'promptpay-qr-payment', 'rice-field-village', 'scams-overcharge', 'school', 'sexual-health-clinic', 'skin-clinic', 'snorkel-boat-tour', 'souvenir-jewelry', 'spirit-house-shrine', 'sport', 'street-food', 'tailor-custom', 'tax-refund', 'thai-cooking-class', 'thai-language-lesson', 'tm30-address-report', 'travel-insurance-claim', 'tuk-tuk-songthaew', 'vegan-vegetarian', 'visa', 'visa-extension', 'volunteering', 'water-park-zoo', 'wedding', 'wifi-coworking-cafe', 'work', 'yoga-retreat'];
const CORE = ['./', 'index.html', 'languages.json', 'presets-index.json', 'allergens.json', 'manifest.webmanifest', 'icon.svg', 'icon-192.png', 'icon-512.png', 'icon-maskable-192.png', 'icon-maskable-512.png', 'apple-touch-icon-180.png', 'i18n/en.json', 'i18n/th.json'];
const MUST = ['index.html', 'languages.json'];   // ohne diese beiden wäre die neue Version kaputt: Installation scheitert, die alte bleibt aktiv
const PACKS = PRESET_IDS.map(id => 'presets/' + id + '.json');   // Pakete kommen nach dem Start (Nachricht 'cache-presets'), nicht beim Installieren
const ALL = CORE.concat(PACKS);   // alles, was offline bereit sein soll
const FILL_PARALLEL = 4;
const abs = u => new URL(u, self.registration.scope).href;   // GitHub Pages liegt unter /en-th-dolmetscher/

// Beim Versionswechsel bereits geladene Pakete aus dem alten Speicher übernehmen: offline bleibt das Satzbuch ohne Lücke nutzbar
function keepOldPacks(c) {
  return caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('dolmetscher-web-') && k !== CACHE).map(k => caches.open(k)
    .then(old => Promise.all(PACKS.map(u => c.match(abs(u)).then(have => have || old.match(abs(u)).then(r => r && c.put(abs(u), r)))))))))
    .catch(() => {});
}

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE)
    .then(c => Promise.all(CORE.map(u => c.add(new Request(abs(u), { cache: 'reload' })).catch(err => { if (MUST.includes(u)) throw err; })))   // Symbole/Daten dürfen fehlen, Seite und Sprachtabelle nicht
      .then(() => keepOldPacks(c)))
    .then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k.startsWith('dolmetscher-web-') && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

const NAV_WAIT_MS = 4000;   // hängendes Netz: nach 4 s die gespeicherte Seite zeigen (falls vorhanden)
const corePaths = new Set(ALL.map(u => new URL(abs(u)).pathname));
const cacheable = url => corePaths.has(url.pathname);   // nur eigene Vorab-Dateien (inkl. presets/), nie fremde Pfade
function offlinePage() {   // kleine Hinweisseite (de/en/th) mit Link zur App, die offline geöffnet werden kann
  const html = '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Offline</title>'
    + '<body style="font:18px system-ui;max-width:32em;margin:2em auto;padding:0 1em"><h1>Offline</h1>'
    + '<p lang="de">Diese Seite ist offline nicht gespeichert.</p><p lang="en">This page is not stored for offline use.</p><p lang="th">หน้านี้ไม่ได้เก็บไว้ใช้แบบออฟไลน์</p>'
    + '<p><a href="' + abs('./') + '">Dolmetscher</a></p></body>';
  return new Response(html, { status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}
const cachedApp = () => caches.match(abs('index.html')).then(r => r || caches.match(abs('./')));

// Seite fragt, wie viele Vorab-Dateien offline bereit sind (Anzeige "Offline bereit")
const status = (c, loading) => Promise.all(ALL.map(u => c.match(abs(u))))
  .then(hits => ({ type: 'offline-status', ok: hits.filter(Boolean).length, total: ALL.length, loading: !!loading }));
let filling = null;
function fillPacks(c, src) {   // fehlende Pakete mit wenigen gleichzeitigen Abrufen laden, Fortschritt melden
  if (filling) return filling;
  let queue = [];
  const worker = () => { const u = queue.shift(); if (!u) return null;
    return fetch(abs(u)).then(r => { if (r.ok && r.status === 200) return c.put(abs(u), r); }).catch(() => {}).then(worker); };
  filling = Promise.all(PACKS.map(u => c.match(abs(u)).then(h => h ? null : u))).then(miss => { queue = miss.filter(Boolean);
    const total = queue.length;
    const timer = setInterval(() => { if (src) status(c, true).then(m => src.postMessage(m)).catch(() => {}); }, 1500);
    return Promise.all(Array.from({ length: Math.min(FILL_PARALLEL, total) }, worker)).then(() => clearInterval(timer));
  }).catch(() => {}).then(() => { filling = null; return status(c).then(m => src && src.postMessage(m)); });
  return filling;
}
self.addEventListener('message', e => {
  if (!e.data || !e.source || (e.data.type !== 'offline-status' && e.data.type !== 'cache-presets')) return;
  if (e.data.type === 'cache-presets') { e.waitUntil(caches.open(CACHE).then(c => fillPacks(c, e.source))); return; }
  e.waitUntil(caches.open(CACHE).then(c => status(c, !!filling)).then(m => e.source.postMessage(m)));
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
    if (!isApp) { e.respondWith(net.catch(() => offlinePage())); return; }   // fremder Pfad (Doku, 404) offline: ehrliche Hinweisseite statt stillem Ersatz
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
    const net = fetch(req, { cache: 'no-cache' }).then(r => {   // Hintergrund-Auffrischung am HTTP-Cache vorbei
      // nur vollständige Antworten (200, nicht 206) und nur bekannte Dateien speichern; Fehler beim Speichern ignorieren
      if (r.ok && r.status === 200 && cacheable(url)) c.put(url.origin + url.pathname, r.clone()).catch(() => {});   // ohne ?query: kein Wachstum durch Varianten
      return r;
    });
    if (hit) { e.waitUntil(net.catch(() => {})); return hit; }
    return net;
  })));
});
