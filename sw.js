// Service Worker der Web-Version: macht die Seite installierbar und das Satzbuch offline nutzbar.
// Nur eigene Dateien (gleicher Ursprung, GET). Übersetzungs-Anfragen (Google, MyMemory) laufen nie hier durch
// und werden nie gespeichert. Neue Version: CACHE hochzählen (nötig bei neuen Dateien; index.html wird ohnehin zuerst vom Netz geholt).
// content-hash: 0af71628e8f4a068
const CACHE = 'dolmetscher-web-v45';
const PRESET_IDS = ['doctor', 'police', 'lostchild', 'pharmacy', 'dentist', 'taxi', 'places', 'airport', 'transport', 'travel', 'hotel', 'restaurant', 'shopping', 'bank', 'answers', 'access', 'spa', 'temple', 'island', 'scooter', 'rental', 'services', 'coworking', 'office', 'adventure-park', 'air-pollution-haze', 'animal-bite-rabies', 'apartment-host-checkin', 'apartment-hunting', 'asthma-inhaler', 'atm-bank-card', 'baby', 'babysitter-housekeeper', 'badminton-tennis', 'bakery-cafe', 'bangkok-skytrain', 'bank-account-opening', 'bank-app-otp-help', 'bank-transfer-abroad', 'beach', 'bicycle-rental', 'bicycle-touring-repair', 'birthday-celebration', 'border-crossing', 'buddhism-etiquette', 'buddhist-ceremony', 'buffet-bbq', 'bus-train', 'business-meeting', 'camping-national-park', 'cannabis-vape', 'car-accident', 'car-breakdown-roadside', 'car-insurance-claim', 'car-rental', 'car-wash-repair', 'card-payment-surcharge', 'cave-waterfall-tour', 'chao-phraya-river-boat', 'childbirth-hospital', 'chronic-conditions', 'cinema-concert', 'coffee-tea-order', 'contractor-renovation', 'convenience-store-7eleven', 'currency-exchange', 'customer-service-complaint', 'customs-duty-free', 'dating-small-talk', 'diabetes-insulin', 'diving', 'diving-medical-clearance', 'doctor-symptom-detail', 'driving-license', 'drone-camera-rules', 'drugs-medication-import', 'earthquake-evacuation', 'elderly-travel', 'electricity-water-bill', 'electronics-mall', 'elephant-sanctuary', 'embassy-consulate', 'emergency', 'epipen-anaphylaxis', 'ev-charging', 'ferry-boat', 'festival', 'fishing-trip', 'flight-delay-change', 'floating-market', 'food-allergy', 'food-delivery', 'food-poisoning-stomach', 'food-spice-level', 'fruit-market-durian', 'funeral-condolence', 'gas-station-parking', 'glasses-lens-repair', 'gold-shop', 'golf', 'golf-caddie-tips', 'grab-ride-hailing', 'grand-palace-museum', 'gym', 'hair-beauty', 'halal-food-muslim', 'hearing-speech-impaired', 'heat-health', 'herbal-traditional-medicine', 'hiking', 'home-repair', 'hospital', 'hospital-payment-insurance', 'hostel-dorm', 'hotel-deposit-dispute', 'hotel-room-problems', 'hotel-theft-report', 'immigration-90day', 'island-hopping', 'jellyfish-marine-sting', 'jet-ski-rental', 'karaoke', 'kayak-national-park', 'kids', 'kids-playground', 'kindergarten-daycare', 'king-royal-respect', 'lab-blood-test', 'laundromat-self-service', 'laundry-deposit', 'laundry-repair', 'locksmith-lockout', 'long-term-lease', 'longtail-boat-charter', 'lost-luggage', 'lost-passport', 'lost-phone', 'lost-wallet-cards', 'luggage-storage', 'market', 'massage', 'massage-prices-booking', 'meditation-retreat', 'mental-health-counseling', 'minivan-airport-transfer', 'mobile-sim', 'monk', 'monsoon-flood-storm', 'mosque-visit', 'mosquito-dengue', 'motorbike-accident', 'motorcycle-taxi', 'muay-thai-gym', 'muay-thai-stadium', 'negotiation', 'neighbors-noise-garbage', 'night-bus-vip', 'night-market-bargain', 'night-train-ticket', 'nightlife', 'nomad', 'notary-document-translation', 'numbers-prices', 'online-shopping-delivery', 'optician-eye-care', 'orchard-farm-visit', 'pet-boarding-flight', 'pets', 'pharmacy-otc', 'pharmacy-prescription-transfer', 'phone-repair-shop', 'photo', 'physiotherapy-injury', 'plumber-electrician-aircon', 'police-checkpoint', 'post-office-parcel', 'power-outage-blackout', 'pregnancy-maternity', 'print-copy-shop', 'private-driver-day-tour', 'promptpay-qr-payment', 'refund-complaint-shop', 'rice-field-village', 'ride-share-dispute', 'rock-climbing', 'scams-overcharge', 'school', 'school-enrollment', 'scooter-rental-damage', 'seafood-by-weight', 'sexual-health-clinic', 'sim-esim-data', 'skin-clinic', 'smoothie-juice-stall', 'snake-bite-venomous', 'snorkel-boat-tour', 'songkran-water-festival', 'souvenir-jewelry', 'spirit-house-shrine', 'sport', 'sprain-fracture-xray', 'stray-dogs-safety', 'street-food', 'street-food-custom-order', 'sunburn-heat-rash', 'surf-kite-lesson', 'tailor-custom', 'tattoo-piercing', 'tax-refund', 'tdac-arrival-card', 'temple-photography', 'thai-cooking-class', 'thai-language-lesson', 'thai-massage-boundaries', 'tipping-service-charge', 'tm30-address-report', 'toothache-emergency', 'tour-agency-booking', 'tourist-police-complaint', 'traffic-fine-police-ticket', 'travel-insurance-claim', 'tuk-tuk-scam-prevention', 'tuk-tuk-songthaew', 'two-price-attraction-tickets', 'used-vehicle-purchase', 'utilities-condo-office', 'vaccination-travel-clinic', 'vegan-vegetarian', 'vet-clinic', 'visa', 'visa-extension', 'visa-run-border', 'volunteering', 'waste-recycling', 'wat-donation-etiquette', 'water-park-zoo', 'wedding', 'wheelchair-mobility', 'wifi-coworking-cafe', 'wildlife-safari', 'work', 'work-permit-office', 'yoga-retreat'];
const CORE = ['./', 'index.html', 'languages.json', 'presets-index.json', 'allergens.json', 'manifest.webmanifest', 'icon.svg', 'icon-192.png', 'icon-512.png', 'icon-maskable-192.png', 'icon-maskable-512.png', 'apple-touch-icon-180.png', 'i18n/en.json', 'i18n/th.json', 'web-extras.js', 'web-qr.js', 'web-search-worker.js'];
const MUST = ['index.html', 'languages.json'];   // ohne diese beiden wäre die neue Version kaputt: Installation scheitert, die alte bleibt aktiv
// Notfall- und Sicherheitspakete zuerst laden; im Datensparmodus (saveData) oder bei knappem Speicher nur diese
const PRIORITY = ['emergency', 'police', 'doctor', 'hospital', 'lostchild', 'pharmacy', 'food-allergy', 'lost-passport', 'car-accident', 'motorbike-accident', 'animal-bite-rabies', 'earthquake-evacuation', 'heat-health', 'answers', 'embassy-consulate', 'lost-wallet-cards', 'taxi', 'travel'];
const FIRST = PRIORITY.filter(id => PRESET_IDS.includes(id));
const PACKS = FIRST.concat(PRESET_IDS.filter(id => !FIRST.includes(id))).map(id => 'presets/' + id + '.json');   // Pakete kommen nach dem Start (Nachricht 'cache-presets'), nicht beim Installieren
const PRIORITY_PACKS = new Set(FIRST.map(id => 'presets/' + id + '.json'));
const MIN_FREE = 20 * 1024 * 1024;   // weniger freier Speicher: nur Notfallpakete laden (alle Pakete zusammen < 1 MB)
const saveData = () => { try { return !!(navigator.connection && navigator.connection.saveData); } catch { return false; } };
const freeBytes = () => { try { return navigator.storage.estimate().then(e => (e.quota || Infinity) - (e.usage || 0)).catch(() => Infinity); } catch { return Promise.resolve(Infinity); } };
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
    .then(() => { try { return self.registration.navigationPreload && self.registration.navigationPreload.enable(); } catch { return null; } })   // Navigation Preload: Netzabruf der Seite startet schon vor dem Worker
    .then(() => self.clients.claim())
    .then(() => self.clients.matchAll({ type: 'window' }).then(cs => cs.forEach(c => c.postMessage({ type: 'sw-version', cache: CACHE })))).catch(() => {}));
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
  .then(hits => ({ type: 'offline-status', ok: hits.filter(Boolean).length, total: ALL.length, loading: !!loading, bytes: packBytes, cache: CACHE }));
let filling = null;
let packBytes = 0;   // in dieser Füllrunde geladene Bytes (für die Fortschrittsanzeige)
const RETRIES = 3, BACKOFF_MS = 500;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const sizeOf = r => { try { return r.clone().arrayBuffer().then(b => b.byteLength, () => 0); } catch { return Promise.resolve(0); } };   // Bytes einer Antwort (Kopie lesen), Fehler zählen als 0
function fetchPack(u, n) {   // Paket laden: bei Netzfehler/5xx bis zu RETRIES Mal mit wachsender Wartezeit (0,5 s, 1 s, 2 s); 4xx sofort aufgeben
  return fetch(abs(u)).then(r => {
    if (r.ok && r.status === 200) return r;
    if (r.status >= 500 && n < RETRIES) return sleep(BACKOFF_MS * 2 ** n).then(() => fetchPack(u, n + 1));
    return null;
  }, err => n < RETRIES ? sleep(BACKOFF_MS * 2 ** n).then(() => fetchPack(u, n + 1)) : null);
}
function fillPacks(c, src, priorityOnly) {   // fehlende Pakete (Notfallpakete zuerst) mit wenigen gleichzeitigen Abrufen laden, Fortschritt melden
  if (filling) return filling;
  let queue = [];
  const worker = () => { const u = queue.shift(); if (!u) return null;
    return fetchPack(u, 0).then(r => { if (!r) return; return sizeOf(r).then(n => { packBytes += n; return c.put(abs(u), r); }); }).catch(() => {}).then(worker); };
  filling = Promise.all([Promise.all(PACKS.map(u => c.match(abs(u)).then(h => h ? null : u))), freeBytes()]).then(([miss, free]) => { queue = miss.filter(Boolean);
    if (priorityOnly || saveData() || free < MIN_FREE) queue = queue.filter(u => PRIORITY_PACKS.has(u));
    const total = queue.length; packBytes = 0;
    const timer = setInterval(() => { if (src) status(c, true).then(m => src.postMessage(m)).catch(() => {}); }, 1500);
    return Promise.all(Array.from({ length: Math.min(FILL_PARALLEL, total) }, worker)).then(() => clearInterval(timer));
  }).catch(() => {}).then(() => { filling = null; return status(c).then(m => src && src.postMessage(m)); });
  return filling;
}
self.addEventListener('message', e => {
  if (e.data && e.data.type === 'audio-opt' && e.source) { e.waitUntil(audioSet(e.data.on === true).then(() => audioStatus(e.source)).catch(() => {})); return; }
  if (!e.data || !e.source || (e.data.type !== 'offline-status' && e.data.type !== 'cache-presets')) return;
  if (e.data.type === 'cache-presets') { e.waitUntil(caches.open(CACHE).then(c => fillPacks(c, e.source, e.data.priorityOnly === true))); return; }
  e.waitUntil(caches.open(CACHE).then(c => status(c, !!filling)).then(m => e.source.postMessage(m)));
});

// Audio-Speicher (nur mit Zustimmung, Runde 25): Dateien unter audio/ (mp3, ogg, m4a, wav) werden erst nach {type:'audio-opt', on:true} gespeichert.
// Die Zustimmung ist ein Marker im Speicher selbst (überlebt Versionswechsel); on:false löscht alles. Die Sprachausgabe des Browsers braucht das nicht.
const AUDIO = 'dolmetscher-audio-v1', AUDIO_RX = /\/audio\/[\w.-]+\.(mp3|ogg|m4a|wav)$/i, AUDIO_MAX = 200, OPT = () => abs('audio-opt');
const audioOn = () => caches.has(AUDIO).then(h => h && caches.open(AUDIO).then(c => c.match(OPT())).then(Boolean)).catch(() => false);
const audioStatus = src => caches.has(AUDIO).then(h => h ? caches.open(AUDIO).then(c => c.keys()).then(k => ({ on: k.some(r => r.url === OPT()), count: Math.max(0, k.length - 1) })) : { on: false, count: 0 })
  .then(m => src.postMessage({ type: 'audio-status', on: m.on, count: m.count })).catch(() => {});
const audioSet = on => on ? caches.open(AUDIO).then(c => c.put(OPT(), new Response('1'))) : caches.delete(AUDIO);
const audioTrim = c => c.keys().then(k => Promise.all(k.filter(r => r.url !== OPT()).slice(0, Math.max(0, k.length - 1 - AUDIO_MAX)).map(r => c.delete(r))));
function audioSlice(hit, req) {   // Teilabrufe (Range) aus dem Speicher bedienen: Safari und iOS verlangen sie bei Audio
  const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.get('range') || '');
  if (!m) return hit;
  return hit.blob().then(b => { const a = m[1] ? +m[1] : 0, z = m[2] ? Math.min(+m[2], b.size - 1) : b.size - 1;
    return new Response(b.slice(a, z + 1), { status: 206, headers: { 'Content-Type': b.type || 'audio/mpeg', 'Content-Range': 'bytes ' + a + '-' + z + '/' + b.size } }); });
}
function audioResponse(e, req, url) {
  const key = url.origin + url.pathname;
  return audioOn().then(on => {
    if (!on) return fetch(req);
    return caches.open(AUDIO).then(c => c.match(key).then(hit => {
      if (hit) return audioSlice(hit, req);
      const full = fetch(key).then(r => (r.ok && r.status === 200) ? c.put(key, r.clone()).then(() => audioTrim(c)).then(() => r) : r);
      if (req.headers.get('range')) { e.waitUntil(full.catch(() => {})); return fetch(req); }   // Teilabruf: Original durchreichen, ganze Datei im Hintergrund holen
      return full;
    }));
  }).catch(() => fetch(req));
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;   // fremde Dienste: Browser direkt, nichts speichern
  if (AUDIO_RX.test(url.pathname)) { e.respondWith(audioResponse(e, req, url)); return; }
  if (req.mode === 'navigate') {                     // Seite: zuerst Netz (Updates), offline aus dem Speicher
    // Nur die App selbst als index.html merken – nicht direkt geöffnete Presets, Doku oder sw.js.
    const isApp = url.pathname === new URL(abs('./')).pathname || url.pathname === new URL(abs('index.html')).pathname;
    const net = Promise.resolve(e.preloadResponse).then(pre => pre || fetch(req)).then(r => {   // vorab gestartete Anfrage nutzen, sonst normal laden
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
