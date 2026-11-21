/* Zusatzwerkzeuge der Web-Version (Runde 24). Wird erst beim Tippen auf den Werkzeug-Knopf (oder einen #pack=-Link) geladen,
   arbeitet komplett offline und sendet nichts: Preis-Check mit manuellem Kurs, Verhandlungshilfe, Reise-Checkliste,
   Wörterbuch aus den Paket-Glossaren, Tour-Guide-Paket als Link, Reisetagebuch, Ton-Trainer, Mikro-Pegel.
   Foto-/Text-Erkennung (OCR) fehlt absichtlich: ohne Modell-Download geht sie nicht offline. */
(function () {
  'use strict';
  var D = ['ศูนย์', 'หนึ่ง', 'สอง', 'สาม', 'สี่', 'ห้า', 'หก', 'เจ็ด', 'แปด', 'เก้า'];
  var UNITS = ['', 'สิบ', 'ร้อย', 'พัน', 'หมื่น', 'แสน'];

  function thaiNum(n) {                 // ganze Zahl 0 .. 9 999 999 als Thai-Wörter
    n = Math.floor(Number(n));
    if (!isFinite(n) || n < 0 || n > 9999999) return '';
    if (n === 0) return D[0];
    var m = Math.floor(n / 1e6), r = n % 1e6, out = m ? thaiNum(m) + 'ล้าน' : '';
    var s = String(r).padStart(6, '0');
    for (var i = 0; i < 6; i++) {
      var d = +s[i], p = 5 - i;
      if (!d) continue;
      if (p === 1 && d === 1) out += 'สิบ';
      else if (p === 1 && d === 2) out += 'ยี่สิบ';
      else if (p === 0 && d === 1 && (r > 10 || m)) out += 'เอ็ด';
      else out += D[d] + UNITS[p];
    }
    return out;
  }

  function convert(amount, rate, toForeign) {   // rate = Baht für 1 Fremdwährung
    var a = Number(amount), r = Number(rate);
    if (!(a >= 0) || !(r > 0)) return null;
    return toForeign ? a / r : a * r;
  }

  function offers(ask) {                // Gegenangebote in Prozent des Preises, auf 10 Baht gerundet
    var a = Number(ask);
    if (!(a > 0)) return [];
    return [50, 65, 80].map(function (p) { return Math.max(1, Math.round(a * p / 100 / 10) * 10 || Math.round(a * p / 100)); });
  }

  function b64u(bytes) {
    var s = '';
    for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }
  function unb64u(t) {
    t = t.replace(/-/g, '+').replace(/_/g, '/');
    while (t.length % 4) t += '=';
    var s = atob(t), b = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) b[i] = s.charCodeAt(i);
    return b;
  }
  async function pipe(bytes, stream) {
    var r = new Response(new Blob([bytes]).stream().pipeThrough(stream));
    return new Uint8Array(await r.arrayBuffer());
  }
  var MAX_CARDS = 60, MAX_TXT = 200, MAX_FRAG = 8000;

  function cleanPack(o) {               // fremde Daten: nur Text, begrenzte Länge und Anzahl
    if (!o || typeof o !== 'object' || !Array.isArray(o.c)) return null;
    var cards = [];
    for (var i = 0; i < o.c.length && cards.length < MAX_CARDS; i++) {
      var c = o.c[i];
      if (Array.isArray(c) && typeof c[0] === 'string' && typeof c[1] === 'string' && c[0].trim() && c[1].trim()) {
        cards.push([c[0].trim().slice(0, MAX_TXT), c[1].trim().slice(0, MAX_TXT)]);
      }
    }
    return cards.length ? { n: String(o.n || 'Pack').trim().slice(0, 40) || 'Pack', c: cards } : null;
  }
  async function packEncode(pack) {     // -> Text für das URL-Fragment (deflate-raw + base64url)
    var p = cleanPack(pack);
    if (!p) throw new Error('empty');
    var bytes = new TextEncoder().encode(JSON.stringify(p));
    var z = await pipe(bytes, new CompressionStream('deflate-raw'));
    var t = b64u(z);
    if (t.length > MAX_FRAG) throw new Error('too big');
    return t;
  }
  // Runde 27: langer Link -> mehrere QR-Codes. Jeder Code ist ein eigener Link (#part=i.n.id.daten); die Seite sammelt die Teile
  // im lokalen Speicher und öffnet das Paket, sobald alle da sind (Prüfsumme id). Nichts wird gesendet.
  var MAX_PARTS = 12;
  function hash4(t) { var h = 2166136261, i; for (i = 0; i < t.length; i++) { h ^= t.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; } return ('0000' + h.toString(36)).slice(-4); }
  function qrParts(base, frag, maxBytes) {     // -> Liste von Links oder null, wenn mehr als MAX_PARTS Teile nötig wären
    var id = hash4(frag), head = base + '#part=', n, per, i, out;
    for (n = 2; n <= MAX_PARTS; n++) {
      per = Math.ceil(frag.length / n);
      if (head.length + String(n).length * 2 + 3 + 4 + per <= maxBytes) {
        out = [];
        for (i = 0; i < n; i++) out.push(head + (i + 1) + '.' + n + '.' + id + '.' + frag.slice(i * per, (i + 1) * per));
        return out;
      }
    }
    return null;
  }
  function partParse(hash) {
    var m = /^#part=(\d{1,2})\.(\d{1,2})\.([a-z0-9]{4})\.([A-Za-z0-9_-]{1,400})$/.exec(hash || '');
    if (!m) return null;
    var i = +m[1], n = +m[2];
    return i >= 1 && n >= 2 && i <= n && n <= MAX_PARTS ? { i: i, n: n, id: m[3], d: m[4] } : null;
  }
  function partAdd(st, pt) {                   // gesammelte Teile + neues Teil -> { st, got, done, frag }
    if (!st || st.id !== pt.id || st.n !== pt.n || typeof st.got !== 'object') st = { id: pt.id, n: pt.n, got: {} };
    st.got[pt.i] = pt.d;
    var got = Object.keys(st.got).length, frag = '', k;
    if (got < st.n) return { st: st, got: got, done: false };
    for (k = 1; k <= st.n; k++) frag += st.got[k] || '';
    return hash4(frag) === st.id ? { st: null, got: got, done: true, frag: frag } : { st: null, got: got, done: false, bad: true };
  }
  function checklistText(title, items, done) { // Offline-Export der Reise-Checkliste als Text
    return title + '\n\n' + items.map(function (x, i) { return (done && done[i] ? '[x] ' : '[ ] ') + x; }).join('\n') + '\n';
  }
  async function packDecode(text) {
    if (typeof text !== 'string' || text.length > MAX_FRAG || !/^[A-Za-z0-9_-]+$/.test(text)) return null;
    try {
      var raw = await pipe(unb64u(text), new DecompressionStream('deflate-raw'));
      if (raw.length > 60000) return null;
      return cleanPack(JSON.parse(new TextDecoder().decode(raw)));
    } catch (e) { return null; }
  }

  var PAIRS = [   // Minimalpaare: gleiche Silbe, anderer Ton
    [['ข้าว', 'khâao', 'rice'], ['ขาว', 'khǎao', 'white'], ['ข่าว', 'khàao', 'news']],
    [['มา', 'maa', 'to come'], ['ม้า', 'máa', 'horse'], ['หมา', 'mǎa', 'dog']],
    [['ไม่', 'mâi', 'not'], ['ไม้', 'máai', 'wood'], ['ใหม่', 'mài', 'new']],
    [['เสือ', 'sǔea', 'tiger'], ['เสื่อ', 'sùea', 'mat'], ['เสื้อ', 'sûea', 'shirt']],
    [['ใกล้', 'glâi', 'near'], ['ไกล', 'glai', 'far']],
    [['คา', 'khaa', 'to be stuck'], ['ข่า', 'khàa', 'galangal'], ['ค่า', 'khâa', 'value, fee'], ['ค้า', 'kháa', 'to trade'], ['ขา', 'khǎa', 'leg']]
  ];
  var CHECK = {
    de: ['Reisepass (mind. 6 Monate gültig) und Kopie', 'Einreisekarte online ausgefüllt (Thailand Digital Arrival Card)', 'Auslandskrankenversicherung', 'Rückflug- oder Weiterreise-Nachweis', 'Bargeld in Baht und Kreditkarte', 'SIM oder eSIM, Offline-Karten geladen', 'Steckdosen-Adapter und Powerbank', 'Medikamente mit Rezept oder Bescheinigung', 'Impfungen geprüft, Mückenschutz, Sonnencreme', 'Notrufnummern 191, 1669, 1155 notiert', 'Adresse der Unterkunft auf Thai gespeichert', 'Kopien der Dokumente getrennt vom Original'],
    en: ['Passport (valid 6+ months) and a copy', 'Arrival card filled in online (Thailand Digital Arrival Card)', 'Travel health insurance', 'Return or onward ticket proof', 'Cash in baht and a credit card', 'SIM or eSIM, offline maps downloaded', 'Plug adapter and power bank', 'Medicines with prescription or certificate', 'Vaccinations checked, mosquito repellent, sun cream', 'Emergency numbers 191, 1669, 1155 noted', 'Hotel address saved in Thai', 'Document copies kept apart from the originals'],
    th: ['หนังสือเดินทาง (เหลืออายุเกินหกเดือน) และสำเนา', 'กรอกบัตรเข้าเมืองออนไลน์แล้ว', 'ประกันสุขภาพการเดินทาง', 'หลักฐานตั๋วขากลับหรือเดินทางต่อ', 'เงินสดบาทและบัตรเครดิต', 'ซิมหรืออีซิม และดาวน์โหลดแผนที่ออฟไลน์', 'ปลั๊กแปลงและพาวเวอร์แบงก์', 'ยาพร้อมใบสั่งแพทย์หรือใบรับรอง', 'ตรวจวัคซีน ยากันยุง ครีมกันแดด', 'จดเบอร์ฉุกเฉิน 191, 1669, 1155', 'บันทึกที่อยู่ที่พักเป็นภาษาไทย', 'เก็บสำเนาเอกสารแยกจากตัวจริง']
  };
  var TXT = {   // eigene Texte, damit i18n/*.json und das Größenbudget von index.html unberührt bleiben
    de: { tools: 'Werkzeuge', close: 'Schließen', price: 'Preis', check: 'Checkliste', dict: 'Wörterbuch', share: 'Teilen', diary: 'Tagebuch', tone: 'Töne', mic: 'Mikro',
      rate: 'Kurs: Baht für 1 Fremdwährung (selbst eintragen, kein Live-Kurs)', baht: 'Preis in Baht', foreign: 'Betrag in Fremdwährung', big: 'Groß zeigen', ask: 'Verlangter Preis in Baht', counter: 'Gegenangebot',
      neg: 'Kann der Preis niedriger sein', search: 'Wort suchen (Deutsch, Englisch oder Thai)', none: 'Nichts gefunden', loading: 'Pakete werden gelesen …', reset: 'Zurücksetzen',
      shareHelp: 'Eigene Karten, eine pro Zeile: Englisch | Thai. Der Link enthält alles; es wird nichts hochgeladen.', packName: 'Name des Pakets', make: 'Link erzeugen', copy: 'Link kopieren', copied: 'Kopiert', tooBig: 'Zu groß für einen Link', saveImp: 'Paket speichern', imported: 'Gespeichert', imp: 'Paket aus Link',
      note: 'Notiz', add: 'Hinzufügen', tags: ['Essen', 'Ort', 'Preis', 'Wichtig'], export: 'Als Datei sichern', play: 'Anhören', quiz: 'Quiz', which: 'Welches Wort hörst du', right: 'Richtig', wrong: 'Falsch, es war',
      start: 'Pegel messen', stop: 'Stopp', noMic: 'Kein Mikrofon-Zugriff', quiet: 'Leise genug', loud: 'Ziemlich laut: Mikro näher an den Mund oder leiseren Ort suchen', veryLoud: 'Sehr laut: Erkennung wird unzuverlässig, lieber Karten zeigen', tooQuiet: 'Zu leise: näher sprechen', micNote: 'Das Audio bleibt auf dem Gerät und wird nicht gespeichert.', male: 'Ich spreche als Mann', thaiSay: 'Auf Thai sagen' },
    en: { tools: 'Tools', close: 'Close', price: 'Price', check: 'Checklist', dict: 'Dictionary', share: 'Share', diary: 'Diary', tone: 'Tones', mic: 'Mic',
      rate: 'Rate: baht for 1 foreign unit (enter it yourself, no live rate)', baht: 'Price in baht', foreign: 'Amount in foreign currency', big: 'Show big', ask: 'Asking price in baht', counter: 'Counter offer',
      neg: 'Can the price be lower', search: 'Search a word (German, English or Thai)', none: 'Nothing found', loading: 'Reading packs …', reset: 'Reset',
      shareHelp: 'Your own cards, one per line: English | Thai. The link holds everything; nothing is uploaded.', packName: 'Pack name', make: 'Create link', copy: 'Copy link', copied: 'Copied', tooBig: 'Too big for a link', saveImp: 'Save pack', imported: 'Saved', imp: 'Pack from link',
      note: 'Note', add: 'Add', tags: ['Food', 'Place', 'Price', 'Important'], export: 'Save as file', play: 'Listen', quiz: 'Quiz', which: 'Which word do you hear', right: 'Correct', wrong: 'Wrong, it was',
      start: 'Measure level', stop: 'Stop', noMic: 'No microphone access', quiet: 'Quiet enough', loud: 'Rather loud: hold the mic closer or find a quieter place', veryLoud: 'Very loud: recognition gets unreliable, show cards instead', tooQuiet: 'Too quiet: speak closer', micNote: 'Audio stays on the device and is not stored.', male: 'I speak as a man', thaiSay: 'Say in Thai' },
    th: { tools: 'เครื่องมือ', close: 'ปิด', price: 'ราคา', check: 'เช็คลิสต์', dict: 'พจนานุกรม', share: 'แชร์', diary: 'ไดอารี่', tone: 'วรรณยุกต์', mic: 'ไมค์',
      rate: 'อัตรา: กี่บาทต่อหนึ่งหน่วยเงินต่างประเทศ (กรอกเอง ไม่ใช่เรตสด)', baht: 'ราคาเป็นบาท', foreign: 'จำนวนเงินต่างประเทศ', big: 'แสดงตัวใหญ่', ask: 'ราคาที่ขาย (บาท)', counter: 'ราคาที่เสนอ',
      neg: 'ลดราคาได้ไหม', search: 'ค้นหาคำ (เยอรมัน อังกฤษ หรือไทย)', none: 'ไม่พบ', loading: 'กำลังอ่านชุดคำศัพท์ …', reset: 'ล้างค่า',
      shareHelp: 'การ์ดของคุณ บรรทัดละหนึ่งใบ: อังกฤษ | ไทย ลิงก์เก็บทุกอย่างไว้ ไม่มีการอัปโหลด', packName: 'ชื่อชุด', make: 'สร้างลิงก์', copy: 'คัดลอกลิงก์', copied: 'คัดลอกแล้ว', tooBig: 'ใหญ่เกินไปสำหรับลิงก์', saveImp: 'บันทึกชุด', imported: 'บันทึกแล้ว', imp: 'ชุดจากลิงก์',
      note: 'บันทึก', add: 'เพิ่ม', tags: ['อาหาร', 'สถานที่', 'ราคา', 'สำคัญ'], export: 'บันทึกเป็นไฟล์', play: 'ฟัง', quiz: 'ควิซ', which: 'ได้ยินคำไหน', right: 'ถูก', wrong: 'ผิด คำตอบคือ',
      start: 'วัดระดับเสียง', stop: 'หยุด', noMic: 'ไม่มีสิทธิ์ใช้ไมโครโฟน', quiet: 'เงียบพอ', loud: 'ค่อนข้างดัง: ถือไมค์ใกล้ปากหรือหาที่เงียบกว่า', veryLoud: 'ดังมาก: การรู้จำเสียงไม่แม่น ให้แสดงการ์ดแทน', tooQuiet: 'เบาเกินไป: พูดใกล้ขึ้น', micNote: 'เสียงอยู่ในเครื่องและไม่ถูกบันทึก', male: 'ฉันพูดเป็นผู้ชาย', thaiSay: 'พูดเป็นภาษาไทย' }
  };
  var TXT25 = {   // Runde 25: QR-Code, Wörterbuch im Hintergrund, Audio-Speicher (opt-in)
    de: { audio: 'Audio', qrAlt: 'QR-Code des Links (lokal erzeugt)', qrTooLong: 'Zu lang für einen QR-Code: den Link kopieren statt scannen.', qrHelp: 'Zum Scannen mit dem anderen Handy; der Code wird auf diesem Gerät berechnet.',
      audioHelp: 'Vorab gespeicherte Audiodateien (Ordner audio/) bleiben offline abrufbar. Aus: es wird nichts gespeichert. Die Sprachausgabe des Browsers braucht diesen Speicher nicht.', audioOn: 'Audio offline speichern', audioClear: 'Audio-Speicher leeren', audioCleared: 'Audio-Speicher geleert', audioNoSw: 'Nicht verfügbar: kein Service Worker.', audioCount: 'Dateien gespeichert' },
    en: { audio: 'Audio', qrAlt: 'QR code of the link (made on this device)', qrTooLong: 'Too long for a QR code: copy the link instead of scanning.', qrHelp: 'Scan it with the other phone; the code is calculated on this device.',
      audioHelp: 'Audio files stored in advance (folder audio/) stay available offline. Off: nothing is stored. The browser voice does not need this storage.', audioOn: 'Keep audio offline', audioClear: 'Clear audio storage', audioCleared: 'Audio storage cleared', audioNoSw: 'Not available: no service worker.', audioCount: 'files stored' },
    th: { audio: 'เสียง', qrAlt: 'คิวอาร์โค้ดของลิงก์ (สร้างบนเครื่องนี้)', qrTooLong: 'ยาวเกินไปสำหรับคิวอาร์โค้ด ให้คัดลอกลิงก์แทนการสแกน', qrHelp: 'สแกนด้วยโทรศัพท์อีกเครื่อง โค้ดคำนวณบนเครื่องนี้',
      audioHelp: 'ไฟล์เสียงที่เก็บไว้ล่วงหน้า (โฟลเดอร์ audio/) ใช้แบบออฟไลน์ได้ ปิด: ไม่เก็บอะไรเลย เสียงพูดของเบราว์เซอร์ไม่ต้องใช้ที่เก็บนี้', audioOn: 'เก็บเสียงไว้ใช้ออฟไลน์', audioClear: 'ล้างที่เก็บเสียง', audioCleared: 'ล้างที่เก็บเสียงแล้ว', audioNoSw: 'ใช้ไม่ได้ ไม่มี service worker', audioCount: 'ไฟล์ที่เก็บไว้' }
  };
  var TXT27 = {   // Runde 27: Checkliste exportieren, Mehrfach-QR für lange Karten-Links
    de: { ckExport: 'Checkliste als Datei sichern', ckTitle: 'Reise-Checkliste Thailand', qrParts: 'Der Link ist zu lang für einen QR-Code und wurde auf {n} Codes verteilt. Alle Codes nacheinander mit dem anderen Handy scannen; die Seite sammelt die Teile und öffnet das Paket, sobald alle da sind.', partSaved: 'Teil {i} von {n} gespeichert. Es fehlen noch {m}.', partPart: 'Teil' },
    en: { ckExport: 'Save checklist as a file', ckTitle: 'Thailand travel checklist', qrParts: 'The link is too long for one QR code and was split into {n} codes. Scan all of them one after another with the other phone; the page collects the parts and opens the pack when all have arrived.', partSaved: 'Part {i} of {n} saved. {m} still missing.', partPart: 'Part' },
    th: { ckExport: 'บันทึกเช็คลิสต์เป็นไฟล์', ckTitle: 'เช็คลิสต์เที่ยวไทย', qrParts: 'ลิงก์ยาวเกินไปสำหรับคิวอาร์โค้ดหนึ่งอัน จึงแบ่งเป็น {n} โค้ด สแกนทุกโค้ดต่อกันด้วยโทรศัพท์อีกเครื่อง หน้านี้จะรวบรวมแล้วเปิดชุดเมื่อได้ครบ', partSaved: 'บันทึกส่วนที่ {i} จาก {n} แล้ว ยังขาดอีก {m}', partPart: 'ส่วน' }
  };
  var NEGO = [['Can you give a discount?', 'ลดหน่อยได้ไหม'], ['That is too expensive.', 'แพงไป'], ['What is your best price?', 'ราคาที่ดีที่สุดเท่าไร'], ['I will look at other shops first.', 'ขอดูร้านอื่นก่อน'], ['Can I get a discount for two?', 'ซื้อสองชิ้นลดได้ไหม']];

  function tr() { var l = (document.documentElement.lang || 'de').slice(0, 2); l = TXT[l] ? l : 'de'; var o = {}, k; for (k in TXT[l]) o[k] = TXT[l][k]; for (k in TXT25[l]) o[k] = TXT25[l][k]; for (k in TXT27[l]) o[k] = TXT27[l][k]; return o; }
  function ck() { var l = (document.documentElement.lang || 'de').slice(0, 2); return CHECK[l] || CHECK.de; }
  function store(k, v) { try { if (v === undefined) return JSON.parse(localStorage.getItem('x24_' + k)); localStorage.setItem('x24_' + k, JSON.stringify(v)); } catch (e) { return null; } return null; }
  function el(tag, props, kids) {
    var e = document.createElement(tag), k;
    for (k in props || {}) { if (k === 'text') e.textContent = props[k]; else if (k === 'on') { for (var ev in props.on) e.addEventListener(ev, props.on[ev]); } else e.setAttribute(k, props[k]); }
    (kids || []).forEach(function (c) { if (c) e.appendChild(c); });
    return e;
  }
  function speak(text) {
    try {
      if (!('speechSynthesis' in window)) return;
      var u = new SpeechSynthesisUtterance(text); u.lang = 'th-TH'; u.rate = 0.85;
      window.speechSynthesis.cancel(); window.speechSynthesis.speak(u);
    } catch (e) { /* ohne Sprachausgabe: nur anzeigen */ }
  }
  function loadScript(src) {            // eigene Datei nachladen (gleicher Ursprung), höchstens einmal
    return new Promise(function (ok, fail) {
      var e = document.createElement('script'); e.src = src; e.onload = ok; e.onerror = function () { e.remove(); fail(new Error(src)); }; document.head.appendChild(e);
    });
  }
  async function qrMany(box, frag, T) {   // Link zu lang für einen Code: auf mehrere verteilen (höchstens MAX_PARTS)
    var parts = qrParts(location.href.split('#')[0], frag, window.DolmetscherQR.maxBytes), i, c;
    if (!parts) { box.textContent = T.qrTooLong; return; }
    box.appendChild(el('p', { text: T.qrParts.replace('{n}', parts.length) }));
    for (i = 0; i < parts.length; i++) {
      c = await qrCanvas(parts[i], T);
      if (!c) { box.textContent = T.qrTooLong; return; }
      box.appendChild(el('p', { text: T.partPart + ' ' + (i + 1) + '/' + parts.length })); box.appendChild(c);
    }
  }
  async function qrCanvas(text, T) {    // QR-Code als Leinwand; null, wenn zu lang
    if (!window.DolmetscherQR) await loadScript('web-qr.js');
    var q = window.DolmetscherQR.encode(text);
    if (!q) return null;
    var n = q.size + 8, k = Math.max(3, Math.floor(320 / n)), c = el('canvas', { width: String(n * k), height: String(n * k), role: 'img', 'aria-label': T.qrAlt, style: 'display:block;margin:8px 0;max-width:100%;height:auto;image-rendering:pixelated;border:1px solid #888' });
    var g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, n * k, n * k); g.fillStyle = '#000';
    for (var y = 0; y < q.size; y++) for (var x = 0; x < q.size; x++) if (q.modules[y][x]) g.fillRect((x + 4) * k, (y + 4) * k, k, k);
    return c;
  }
  function bigCard(lines) {             // Vollbild-Karte zum Vorzeigen, Tippen schließt
    var o = el('div', { role: 'dialog', 'aria-modal': 'true', tabindex: '0', style: 'position:fixed;inset:0;z-index:99999;background:#000;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:16px;gap:12px;cursor:pointer' });
    lines.forEach(function (t, i) { o.appendChild(el('div', { text: t, style: 'font-size:' + (i ? 'clamp(24px,7vw,56px)' : 'clamp(48px,20vw,160px)') + ';font-weight:700;line-height:1.15;word-break:break-word' })); });
    function off() { o.remove(); }
    o.addEventListener('click', off); o.addEventListener('keydown', function (e) { if (e.key === 'Escape' || e.key === 'Enter') off(); });
    (dlg && dlg.open ? dlg : document.body).appendChild(o); o.focus();
  }
  function field(label, id, type, val) {
    var i = el('input', { id: id, type: type || 'text', inputmode: type === 'number' ? 'decimal' : 'text', autocomplete: 'off', style: 'width:100%;box-sizing:border-box;font:inherit;padding:6px' });
    if (val != null) i.value = val;
    return { box: el('label', { style: 'display:block;margin:8px 0' }, [el('span', { text: label, style: 'display:block' }), i]), input: i };
  }
  function btn(text, fn) { return el('button', { type: 'button', class: 'small', text: text, on: { click: fn }, style: 'margin:4px 4px 4px 0' }); }
  function out(box) { var d = el('div', { role: 'status', 'aria-live': 'polite', style: 'margin:6px 0;font-weight:600' }); box.appendChild(d); return d; }
  function say(p, th) {                // Fragen enden auf ครับ/คะ, Aussagen auf ครับ/ค่ะ
    var q = /(ไหม|เท่าไร|ไหน|อะไร|กี่)$/.test(th);
    return th + (p.male ? 'ครับ' : q ? 'คะ' : 'ค่ะ');
  }

  var TABS = {
    price: function (box, T) {
      var cur = store('rate') || { code: 'EUR', rate: '' };
      var code = field('ISO', 'x24code', 'text', cur.code), rate = field(T.rate, 'x24rate', 'number', cur.rate);
      var baht = field(T.baht, 'x24baht', 'number'), fx = field(T.foreign, 'x24fx', 'number');
      var o = out(box);
      function sync(from) {
        store('rate', { code: code.input.value.slice(0, 4), rate: rate.input.value });
        var r = rate.input.value, v;
        if (from === 'b') { v = convert(baht.input.value, r, true); fx.input.value = v == null ? '' : v.toFixed(2); }
        else { v = convert(fx.input.value, r, false); baht.input.value = v == null ? '' : String(Math.round(v)); }
        var b = Math.round(Number(baht.input.value));
        o.textContent = b > 0 ? b + ' ฿ = ' + thaiNum(b) + ' บาท' : '';
      }
      baht.input.addEventListener('input', function () { sync('b'); }); fx.input.addEventListener('input', function () { sync('f'); }); rate.input.addEventListener('input', function () { sync('b'); }); code.input.addEventListener('input', function () { sync('b'); });
      [code.box, rate.box, baht.box, fx.box].forEach(function (n) { box.insertBefore(n, o); });
      box.appendChild(btn(T.big, function () { var b = Math.round(Number(baht.input.value)); if (b > 0) bigCard([String(b), thaiNum(b) + ' บาท']); }));
      box.appendChild(el('hr'));
      var ask = field(T.ask, 'x24ask', 'number'), male = el('label', { style: 'display:block' }, [el('input', { type: 'checkbox', id: 'x24male' }), el('span', { text: ' ' + T.male })]);
      var res = el('div'); box.appendChild(ask.box); box.appendChild(male); box.appendChild(res);
      function neg() {
        res.textContent = '';
        offers(ask.input.value).forEach(function (n) {
          res.appendChild(btn(T.counter + ' ' + n + ' ฿', function () { bigCard([String(n), thaiNum(n) + ' บาท', say({ male: male.firstChild.checked }, 'ได้ไหม')]); }));
        });
        if (offers(ask.input.value).length) NEGO.forEach(function (p) { res.appendChild(el('div', { style: 'margin:6px 0' }, [btn(say({ male: male.firstChild.checked }, p[1]), function () { bigCard([say({ male: male.firstChild.checked }, p[1]), p[0]]); speak(say({ male: male.firstChild.checked }, p[1])); })])); });
      }
      ask.input.addEventListener('input', neg);
    },
    check: function (box, T) {
      var items = ck(), done = store('check') || {};
      items.forEach(function (txt, i) {
        var c = el('input', { type: 'checkbox' }); c.checked = !!done[i];
        c.addEventListener('change', function () { done[i] = c.checked; store('check', done); });
        box.appendChild(el('label', { style: 'display:block;margin:6px 0' }, [c, el('span', { text: ' ' + txt })]));
      });
      box.appendChild(btn(T.reset, function () { store('check', {}); box.textContent = ''; TABS.check(box, T); }));
      box.appendChild(btn(T.ckExport, function () {      // offline: Textdatei aus dem Gedächtnis des Geräts, kein Upload
        var a = el('a', { href: URL.createObjectURL(new Blob([checklistText(T.ckTitle, items, done)], { type: 'text/plain;charset=utf-8' })), download: 'reise-checkliste.txt' });
        document.body.appendChild(a); a.click(); a.remove();
      }));
    },
    dict: function (box, T) {
      var q = field(T.search, 'x24q', 'search'), res = el('div', { 'aria-live': 'polite' }), all = null, wk = null, wkReady = null, qid = 0;
      function useWorker() {              // Suche im Hintergrund (Worker); ohne Worker oder bei Fehler weiter unten im Hauptthread
        if (wk === false) return false;
        if (wk) return true;
        try {
          wk = new Worker('web-search-worker.js');
          wk.addEventListener('error', function () { wk = false; wkReady = null; });
          wkReady = fetch('presets-index.json').then(function (r) { return r.json(); }).then(function (j) {
            return new Promise(function (ok) { wk.addEventListener('message', function h(ev) { if (ev.data && ev.data.t === 'ready') { wk.removeEventListener('message', h); ok(); } }); wk.postMessage({ t: 'load', ids: j.packs.map(function (p) { return p.id; }) }); });
          });
          return true;
        } catch (e) { wk = false; return false; }
      }
      function askWorker(s) {
        var id = ++qid;
        return wkReady.then(function () { return new Promise(function (ok, fail) {
          function h(ev) { if (ev.data && ev.data.t === 'hits' && ev.data.id === id) { wk.removeEventListener('message', h); ok(ev.data.hits); } }
          wk.addEventListener('message', h); wk.postMessage({ t: 'q', id: id, q: s, limit: 40 });
          setTimeout(function () { wk && wk.removeEventListener && wk.removeEventListener('message', h); fail(new Error('timeout')); }, 8000);
        }); });
      }
      box.stopFn = function () { if (wk) { try { wk.terminate(); } catch (e) { /* schon beendet */ } wk = null; wkReady = null; } };
      box.appendChild(q.box); box.appendChild(res);
      async function load() {
        if (all) return all;
        res.textContent = T.loading; all = [];
        var ids = [];
        try { ids = (await (await fetch('presets-index.json')).json()).packs.map(function (p) { return p.id; }); } catch (e) { return all; }
        var seen = {}, i = 0;
        async function worker() { while (i < ids.length) { var id = ids[i++]; try { var d = await (await fetch('presets/' + id + '.json')).json(); (d.glossary || []).forEach(function (g) { var k = g.en + '|' + g.th; if (!seen[k]) { seen[k] = 1; all.push(g); } }); } catch (e) { /* Paket fehlt offline */ } } }
        await Promise.all([worker(), worker(), worker(), worker(), worker(), worker()]);
        return all;
      }
      var timer = 0;
      q.input.addEventListener('input', function () {
        clearTimeout(timer);
        timer = setTimeout(async function () {
          var s = q.input.value.trim().toLowerCase(), hits = null;
          if (s && useWorker()) { res.textContent = T.loading; try { hits = await askWorker(s); } catch (e) { wk = false; hits = null; } }
          if (!hits) { await load(); if (s) hits = all.filter(function (g) { return g.en.toLowerCase().indexOf(s) >= 0 || g.th.indexOf(s) >= 0; }).slice(0, 40); }
          res.textContent = '';
          if (!s) return;
          if (!hits.length) { res.textContent = T.none; return; }
          hits.forEach(function (g) { res.appendChild(el('div', {}, [btn(g.th, function () { speak(g.th); bigCard([g.th, g.en]); }), el('span', { text: g.en })])); });
        }, 150);
      });
    },
    share: function (box, T) {
      var name = field(T.packName, 'x24pn', 'text'), ta = el('textarea', { rows: '6', style: 'width:100%;box-sizing:border-box;font:inherit', 'aria-label': T.shareHelp });
      var o = out(box), qrBox = el('div', { 'aria-live': 'polite' }), link = el('input', { readonly: 'readonly', style: 'width:100%;box-sizing:border-box;font:inherit' });
      box.insertBefore(el('p', { text: T.shareHelp }), o); box.insertBefore(name.box, o); box.insertBefore(ta, o);
      box.appendChild(btn(T.make, async function () {
        var cards = ta.value.split('\n').map(function (l) { var p = l.split('|'); return p.length > 1 ? [p[0], p.slice(1).join('|')] : null; }).filter(Boolean);
        try {
          var t = await packEncode({ n: name.input.value, c: cards });
          link.value = location.href.split('#')[0] + '#pack=' + t; o.textContent = '';
          qrBox.textContent = '';
          try {
            var c = await qrCanvas(link.value, T);
            if (c) { qrBox.appendChild(el('p', { text: T.qrHelp })); qrBox.appendChild(c); } else await qrMany(qrBox, t, T);
          } catch (e2) { qrBox.textContent = T.qrTooLong; }
        } catch (e) { o.textContent = T.tooBig; }
      }));
      box.appendChild(btn(T.copy, function () { try { navigator.clipboard.writeText(link.value); o.textContent = T.copied; } catch (e) { link.select(); } }));
      box.appendChild(link); box.appendChild(qrBox);
      var saved = store('packs') || [];
      saved.forEach(function (p) { box.appendChild(btn(p.n, function () { showPack(p, T); })); });
    },
    diary: function (box, T) {
      var log = store('diary') || [], tag = el('select', { 'aria-label': T.tags.join(', '), style: 'font:inherit' }), note = field(T.note, 'x24note', 'text'), list = el('div');
      T.tags.forEach(function (t, i) { tag.appendChild(el('option', { value: String(i), text: t })); });
      function draw() { list.textContent = ''; log.slice().reverse().forEach(function (e) { list.appendChild(el('div', { text: e.d + ' [' + T.tags[e.t] + '] ' + e.x, style: 'margin:4px 0' })); }); }
      box.appendChild(note.box); box.appendChild(tag);
      box.appendChild(btn(T.add, function () { var x = note.input.value.trim(); if (!x) return; log.push({ d: new Date().toISOString().slice(0, 16).replace('T', ' '), t: +tag.value, x: x.slice(0, 500) }); store('diary', log.slice(-300)); note.input.value = ''; draw(); }));
      box.appendChild(btn(T.export, function () {
        var md = '# Reisetagebuch\n\n' + log.map(function (e) { return '- ' + e.d + ' **' + T.tags[e.t] + '** ' + e.x; }).join('\n') + '\n';
        var a = el('a', { href: URL.createObjectURL(new Blob([md], { type: 'text/markdown' })), download: 'reisetagebuch.md' });
        document.body.appendChild(a); a.click(); a.remove();
      }));
      box.appendChild(list); draw();
    },
    tone: function (box, T) {
      var o = out(box), choices = el('div');
      PAIRS.forEach(function (g) {
        box.insertBefore(el('div', { style: 'margin:6px 0' }, g.map(function (w) { return btn(w[0] + ' ' + w[1] + ' = ' + w[2], function () { speak(w[0]); }); })), o);
      });
      box.appendChild(choices);
      box.appendChild(btn(T.quiz, function () {
        var g = PAIRS[Math.floor(Math.random() * PAIRS.length)], w = g[Math.floor(Math.random() * g.length)];
        o.textContent = T.which; choices.textContent = ''; speak(w[0]);
        g.forEach(function (c) { choices.appendChild(btn(c[2], function () { o.textContent = c === w ? T.right : T.wrong + ' ' + w[0] + ' (' + w[2] + ')'; })); });
        choices.appendChild(btn(T.play, function () { speak(w[0]); }));
      }));
    },
    audio: function (box, T) {
      var sw = navigator.serviceWorker, st = store('audio') === true, cb = el('input', { type: 'checkbox', id: 'x25audio' }), o = out(box);
      cb.checked = st;
      function send(on) { try { if (sw && sw.controller) { sw.controller.postMessage({ type: 'audio-opt', on: on }); return true; } } catch (e) { /* ohne Worker */ } return false; }
      function onMsg(ev) { if (ev.data && ev.data.type === 'audio-status') o.textContent = ev.data.on ? ev.data.count + ' ' + T.audioCount : ''; }
      if (sw) sw.addEventListener('message', onMsg);
      box.stopFn = function () { if (sw) sw.removeEventListener('message', onMsg); };
      box.insertBefore(el('p', { text: T.audioHelp }), o);
      box.insertBefore(el('label', {}, [cb, el('span', { text: ' ' + T.audioOn })]), o);
      if (!sw || !sw.controller) { o.textContent = T.audioNoSw; cb.disabled = true; } else if (st) send(true);
      cb.addEventListener('change', function () { store('audio', cb.checked); send(cb.checked); });
      box.appendChild(btn(T.audioClear, function () { cb.checked = false; store('audio', false); send(false); o.textContent = T.audioCleared; }));
    },
    mic: function (box, T) {
      var o = out(box), bar = el('div', { style: 'height:16px;background:#888;width:100%' }), lvl = el('div', { style: 'height:16px;background:#2a9d4a;width:0' });
      bar.appendChild(lvl); box.appendChild(el('p', { text: T.micNote })); box.appendChild(bar);
      var ctx, stream, raf = 0;
      function stop() { cancelAnimationFrame(raf); if (stream) stream.getTracks().forEach(function (t) { t.stop(); }); if (ctx) ctx.close(); ctx = stream = null; }
      box.stopFn = stop;
      box.appendChild(btn(T.start, async function () {
        stop();
        try {
          stream = await navigator.mediaDevices.getUserMedia({ audio: true }); ctx = new (window.AudioContext || window.webkitAudioContext)();
          var an = ctx.createAnalyser(); an.fftSize = 1024; ctx.createMediaStreamSource(stream).connect(an); var buf = new Float32Array(an.fftSize);
          (function tick() {
            an.getFloatTimeDomainData(buf); var s = 0; for (var i = 0; i < buf.length; i++) s += buf[i] * buf[i];
            var db = 20 * Math.log10(Math.sqrt(s / buf.length) || 1e-6), pct = Math.max(0, Math.min(100, (db + 70) * 100 / 70));
            lvl.style.width = pct + '%'; lvl.style.background = db > -15 ? '#c0392b' : db > -30 ? '#e6a700' : '#2a9d4a';
            o.textContent = Math.round(db) + ' dB  ' + (db > -15 ? T.veryLoud : db > -30 ? T.loud : db < -55 ? T.tooQuiet : T.quiet);
            raf = requestAnimationFrame(tick);
          })();
        } catch (e) { o.textContent = T.noMic; }
      }));
      box.appendChild(btn(T.stop, function () { stop(); }));
    }
  };

  function showPack(p, T) {
    var d = openDlg(), body = d.querySelector('.x24body'); body.textContent = '';
    body.appendChild(el('h3', { text: p.n }));
    p.c.forEach(function (c) { body.appendChild(el('div', {}, [btn(c[1], function () { speak(c[1]); bigCard([c[1], c[0]]); }), el('span', { text: c[0] })])); });
    if (T && !(store('packs') || []).some(function (x) { return x.n === p.n && x.c.length === p.c.length; })) {
      body.appendChild(btn(T.saveImp, function () { var s = store('packs') || []; s.push(p); store('packs', s.slice(-10)); body.appendChild(el('p', { text: T.imported })); }));
    }
  }
  var dlg = null, curTab = 'price';
  function openDlg() {
    if (!dlg) {
      dlg = el('dialog', { id: 'extrasDlg', 'aria-labelledby': 'x24title', style: 'max-width:min(640px,96vw);width:96vw;max-height:92vh;overflow:auto' });
      dlg.addEventListener('close', function () { var b = dlg.querySelector('.x24body'); if (b && b.stopFn) b.stopFn(); });
      document.body.appendChild(dlg);
    }
    dlg.textContent = '';
    var T = tr(), tabs = el('div', { role: 'tablist' }), body = el('div', { class: 'x24body' });
    dlg.appendChild(el('h2', { id: 'x24title', text: T.tools })); dlg.appendChild(tabs); dlg.appendChild(body);
    dlg.appendChild(btn(T.close, function () { dlg.close(); }));
    Object.keys(TABS).forEach(function (k) {
      tabs.appendChild(el('button', { type: 'button', class: 'small', role: 'tab', 'aria-selected': String(k === curTab), text: T[k], style: 'margin:2px', on: { click: function () { curTab = k; if (body.stopFn) body.stopFn(); openTab(); } } }));
    });
    function openTab() { openDlg(); }
    TABS[curTab](body, T);
    if (!dlg.open) dlg.showModal();
    return dlg;
  }

  async function importFromHash() {
    var pt = partParse(location.hash || ''), T = tr();
    if (pt) {
      var r = partAdd(store('parts'), pt);
      store('parts', r.st);
      if (r.done) { var pk = await packDecode(r.frag); if (pk) showPack(pk, T); return !!pk; }
      var d = openDlg(), body = d.querySelector('.x24body'); body.textContent = '';
      body.appendChild(el('p', { role: 'status', text: T.partSaved.replace('{i}', pt.i).replace('{n}', pt.n).replace('{m}', pt.n - r.got) }));
      return !r.bad;
    }
    var m = /^#pack=([A-Za-z0-9_-]+)$/.exec(location.hash || '');
    if (!m) return false;
    var p = await packDecode(m[1]);
    if (p) showPack(p, tr());
    return !!p;
  }

  var api = { thaiNum: thaiNum, convert: convert, offers: offers, packEncode: packEncode, packDecode: packDecode, qrParts: qrParts, partParse: partParse, partAdd: partAdd, checklistText: checklistText, hash4: hash4, cleanPack: cleanPack, PAIRS: PAIRS, CHECK: CHECK, open: openDlg, importFromHash: importFromHash, tr: tr };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else { window.DolmetscherExtras = api; }
})();
