// Web Worker für die Wörterbuch-Suche (Runde 25): liest die Pakete und sucht im Hintergrund, damit die Oberfläche beim Tippen nicht ruckelt.
// Nur eigene Dateien (presets/*.json, gleicher Ursprung), nichts wird gesendet. Nachrichten:
//   { t: 'load', ids: [...] }                  -> { t: 'ready', n: Anzahl Einträge }
//   { t: 'q', id: Zahl, q: 'text', limit: 40 } -> { t: 'hits', id: Zahl, hits: [{ en, th, k: 'g' | 'p' }] }
(function () {
  'use strict';
  var entries = [], seen = {};
  function add(en, th, kind) {
    if (typeof en !== 'string' || typeof th !== 'string' || !en || !th) return;
    var key = en + '|' + th;
    if (seen[key]) return;
    seen[key] = 1;
    entries.push({ en: en, th: th, k: kind, l: en.toLowerCase() });
  }
  function addPack(d) {
    if (!d || typeof d !== 'object') return;
    (Array.isArray(d.glossary) ? d.glossary : []).forEach(function (g) { if (g) add(g.en, g.th, 'g'); });
    (Array.isArray(d.phrases) ? d.phrases : []).forEach(function (p) { if (p) add(p.en, p.th, 'p'); });
  }
  function search(q, limit) {                                     // Wörter vor Sätzen; Treffer am Wortanfang vor Treffern mitten im Wort
    var s = String(q || '').trim().toLowerCase();
    if (!s) return [];
    var res = [];
    entries.forEach(function (e) {
      var i = e.l.indexOf(s), j = e.th.indexOf(s);
      if (i < 0 && j < 0) return;
      var start = i === 0 || (i > 0 && e.l.charAt(i - 1) === ' ') || j === 0;
      res.push({ e: e, r: (e.k === 'g' ? 0 : 2) + (start ? 0 : 1) });
    });
    res.sort(function (a, b) { return a.r - b.r; });
    return res.slice(0, limit || 40).map(function (x) { return { en: x.e.en, th: x.e.th, k: x.e.k }; });
  }
  function reset() { entries = []; seen = {}; }
  async function load(ids) {                                      // höchstens 6 Abrufe gleichzeitig
    reset();
    var i = 0;
    async function lane() {
      while (i < ids.length) {
        var id = ids[i++];
        if (typeof id !== 'string' || !/^[a-z0-9_-]{1,32}$/.test(id)) continue;
        try { var r = await fetch('presets/' + id + '.json'); if (r.ok) addPack(await r.json()); } catch (e) { /* Paket fehlt offline */ }
      }
    }
    await Promise.all([lane(), lane(), lane(), lane(), lane(), lane()]);
    return entries.length;
  }
  var api = { addPack: addPack, search: search, reset: reset, size: function () { return entries.length; } };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else if (typeof self !== 'undefined' && typeof importScripts === 'function') {
    self.onmessage = async function (e) {
      var m = e.data || {};
      if (m.t === 'load' && Array.isArray(m.ids)) self.postMessage({ t: 'ready', n: await load(m.ids.slice(0, 400)) });
      else if (m.t === 'q') self.postMessage({ t: 'hits', id: m.id, hits: search(m.q, Math.min(Number(m.limit) || 40, 100)) });
    };
  }
})();
