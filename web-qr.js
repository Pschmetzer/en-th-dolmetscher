// QR-Code-Erzeugung ohne Fremdbibliothek (Runde 25): Bytemodus, Fehlerkorrektur L, Version 1 bis 10 (bis 271 Bytes UTF-8).
// Alles läuft lokal im Browser; es wird nichts gesendet. Nutzung: DolmetscherQR.encode('text') -> { size, modules, version, mask }.
(function () {
  'use strict';
  var RAW = [26, 44, 70, 100, 134, 172, 196, 242, 292, 346];     // Codewörter je Version (Daten + Korrektur)
  var BLOCKS = [1, 1, 1, 1, 1, 2, 2, 2, 2, 4];                    // Blöcke bei Stufe L
  var ECC = [7, 10, 15, 20, 26, 18, 20, 24, 30, 18];              // Korrekturwörter je Block
  var ALIGN = [[], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];
  var MAX_VERSION = 10;

  function toUtf8(text) {
    var out = [], s = unescape(encodeURIComponent(String(text))), i;
    for (i = 0; i < s.length; i++) out.push(s.charCodeAt(i));
    return out;
  }
  function dataCapacity(v) { return RAW[v - 1] - ECC[v - 1] * BLOCKS[v - 1]; }
  function mul(x, y) {                                           // Multiplikation in GF(256), Polynom 0x11D
    var z = 0, i;
    for (i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >>> 7) * 0x11D); z ^= ((y >>> i) & 1) * x; }
    return z;
  }
  function divisor(degree) {
    var res = [], i, j, root = 1;
    for (i = 0; i < degree - 1; i++) res.push(0);
    res.push(1);
    for (i = 0; i < degree; i++) {
      for (j = 0; j < res.length; j++) { res[j] = mul(res[j], root); if (j + 1 < res.length) res[j] ^= res[j + 1]; }
      root = mul(root, 2);
    }
    return res;
  }
  function remainder(data, div) {
    var res = div.map(function () { return 0; });
    data.forEach(function (b) {
      var f = b ^ res.shift();
      res.push(0);
      div.forEach(function (c, i) { res[i] ^= mul(c, f); });
    });
    return res;
  }
  function bit(x, i) { return ((x >>> i) & 1) !== 0; }

  function codewords(bytes, v) {                                  // Datenbits, Füllbytes, Blöcke, Korrektur, Verschränkung
    var cap = dataCapacity(v), bits = [], i;
    function put(val, len) { for (var k = len - 1; k >= 0; k--) bits.push((val >>> k) & 1); }
    put(4, 4); put(bytes.length, v < 10 ? 8 : 16);
    bytes.forEach(function (b) { put(b, 8); });
    put(0, Math.min(4, cap * 8 - bits.length));
    while (bits.length % 8) bits.push(0);
    var data = [];
    for (i = 0; i < bits.length; i += 8) { var n = 0; for (var k = 0; k < 8; k++) n = n * 2 + bits[i + k]; data.push(n); }
    for (i = 0xEC; data.length < cap; i ^= 0xEC ^ 0x11) data.push(i);
    var nb = BLOCKS[v - 1], el = ECC[v - 1], raw = RAW[v - 1], nShort = nb - raw % nb, shortLen = Math.floor(raw / nb);
    var blocks = [], div = divisor(el), pos = 0;
    for (i = 0; i < nb; i++) {
      var dat = data.slice(pos, pos + shortLen - el + (i < nShort ? 0 : 1));
      pos += dat.length;
      var ecc = remainder(dat, div);
      if (i < nShort) dat.push(0);
      blocks.push(dat.concat(ecc));
    }
    var out = [];
    for (i = 0; i < blocks[0].length; i++) {
      blocks.forEach(function (b, j) { if (i !== shortLen - el || j >= nShort) out.push(b[i]); });
    }
    return out;
  }

  function Grid(v) {
    this.size = 17 + v * 4; this.v = v;
    this.m = []; this.f = [];
    for (var y = 0; y < this.size; y++) { this.m.push(new Array(this.size).fill(false)); this.f.push(new Array(this.size).fill(false)); }
  }
  Grid.prototype.setF = function (x, y, dark) { this.m[y][x] = dark; this.f[y][x] = true; };
  Grid.prototype.finder = function (cx, cy) {
    for (var dy = -4; dy <= 4; dy++) for (var dx = -4; dx <= 4; dx++) {
      var d = Math.max(Math.abs(dx), Math.abs(dy)), x = cx + dx, y = cy + dy;
      if (x >= 0 && x < this.size && y >= 0 && y < this.size) this.setF(x, y, d !== 2 && d !== 4);
    }
  };
  Grid.prototype.align = function (cx, cy) {
    for (var dy = -2; dy <= 2; dy++) for (var dx = -2; dx <= 2; dx++) this.setF(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  };
  Grid.prototype.formatBits = function (mask) {                   // Stufe L = 01
    var data = (1 << 3) | mask, rem = data, i, s = this.size;
    for (i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    var bits = ((data << 10) | rem) ^ 0x5412;
    for (i = 0; i <= 5; i++) this.setF(8, i, bit(bits, i));
    this.setF(8, 7, bit(bits, 6)); this.setF(8, 8, bit(bits, 7)); this.setF(7, 8, bit(bits, 8));
    for (i = 9; i < 15; i++) this.setF(14 - i, 8, bit(bits, i));
    for (i = 0; i < 8; i++) this.setF(s - 1 - i, 8, bit(bits, i));
    for (i = 8; i < 15; i++) this.setF(8, s - 15 + i, bit(bits, i));
    this.setF(8, s - 8, true);
  };
  Grid.prototype.versionBits = function () {
    if (this.v < 7) return;
    var rem = this.v, i;
    for (i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1F25);
    var bits = (this.v << 12) | rem;
    for (i = 0; i < 18; i++) {
      var a = this.size - 11 + (i % 3), b = Math.floor(i / 3), c = bit(bits, i);
      this.setF(a, b, c); this.setF(b, a, c);
    }
  };
  Grid.prototype.patterns = function () {
    var s = this.size, i, p = ALIGN[this.v - 1], last = p.length - 1;
    for (i = 0; i < s; i++) { this.setF(6, i, i % 2 === 0); this.setF(i, 6, i % 2 === 0); }
    this.finder(3, 3); this.finder(s - 4, 3); this.finder(3, s - 4);
    for (i = 0; i < p.length; i++) for (var j = 0; j < p.length; j++) {
      if (!((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0))) this.align(p[i], p[j]);
    }
    this.formatBits(0); this.versionBits();                       // Platz reservieren; Format wird nach der Maskenwahl neu geschrieben
  };
  Grid.prototype.place = function (cw) {
    var i = 0, s = this.size;
    for (var right = s - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (var vert = 0; vert < s; vert++) for (var j = 0; j < 2; j++) {
        var x = right - j, up = ((right + 1) & 2) === 0, y = up ? s - 1 - vert : vert;
        if (!this.f[y][x] && i < cw.length * 8) { this.m[y][x] = bit(cw[i >>> 3], 7 - (i & 7)); i++; }
      }
    }
  };
  var MASKS = [
    function (x, y) { return (x + y) % 2 === 0; }, function (x, y) { return y % 2 === 0; },
    function (x, y) { return x % 3 === 0; }, function (x, y) { return (x + y) % 3 === 0; },
    function (x, y) { return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0; },
    function (x, y) { return x * y % 2 + x * y % 3 === 0; }, function (x, y) { return (x * y % 2 + x * y % 3) % 2 === 0; },
    function (x, y) { return ((x + y) % 2 + x * y % 3) % 2 === 0; }
  ];
  Grid.prototype.mask = function (k) {
    for (var y = 0; y < this.size; y++) for (var x = 0; x < this.size; x++) if (!this.f[y][x] && MASKS[k](x, y)) this.m[y][x] = !this.m[y][x];
  };
  function penalty(m) {                                           // Regeln 1 bis 4 der Norm
    var n = m.length, p = 0, x, y, dark = 0, run, i;
    function line(get) {
      run = 1;
      for (i = 1; i < n; i++) { if (get(i) === get(i - 1)) { run++; if (run === 5) p += 3; else if (run > 5) p++; } else run = 1; }
      var s = ''; for (i = 0; i < n; i++) s += get(i) ? '1' : '0';
      for (i = s.indexOf('1011101'); i >= 0; i = s.indexOf('1011101', i + 1)) {   // Suchmuster 1:1:3:1:1 mit 4 hellen Feldern davor oder danach
        if (s.substr(i + 7, 4) === '0000' || (i >= 4 && s.substr(i - 4, 4) === '0000')) p += 40;
      }
    }
    for (y = 0; y < n; y++) line(function (k) { return m[y][k]; });
    for (x = 0; x < n; x++) line(function (k) { return m[k][x]; });
    for (y = 0; y < n - 1; y++) for (x = 0; x < n - 1; x++) if (m[y][x] === m[y][x + 1] && m[y][x] === m[y + 1][x] && m[y][x] === m[y + 1][x + 1]) p += 3;
    for (y = 0; y < n; y++) for (x = 0; x < n; x++) if (m[y][x]) dark++;
    return p + 10 * (Math.ceil(Math.abs(dark * 20 - n * n * 10) / (n * n)) - 1);
  }
  function encode(text) {
    var bytes = toUtf8(text), v = 1;
    while (v <= MAX_VERSION && dataCapacity(v) * 8 < 4 + (v < 10 ? 8 : 16) + bytes.length * 8) v++;
    if (v > MAX_VERSION) return null;                             // zu lang für diese Ausbaustufe
    var cw = codewords(bytes, v), best = null, bestMask = 0, bestPen = Infinity, k;
    for (k = 0; k < 8; k++) {
      var g = new Grid(v); g.patterns(); g.place(cw); g.mask(k); g.formatBits(k);
      var pen = penalty(g.m);
      if (pen < bestPen) { bestPen = pen; best = g; bestMask = k; }
    }
    return { size: best.size, modules: best.m, version: v, mask: bestMask };
  }
  function toPath(q) {                                            // eine Pfadangabe für SVG (Einheitsquadrate)
    var d = '';
    for (var y = 0; y < q.size; y++) for (var x = 0; x < q.size; x++) if (q.modules[y][x]) d += 'M' + x + ' ' + y + 'h1v1h-1z';
    return d;
  }
  var api = { encode: encode, toPath: toPath, maxBytes: dataCapacity(MAX_VERSION) - 3 };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else window.DolmetscherQR = api;
})();
