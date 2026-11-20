# ruff: noqa: E501
"""Runde 25 (Web): QR-Code ohne Fremdbibliothek (web-qr.js) und seine Einbindung im Tab „Teilen“."""
import json
import pathlib
import re
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
QR = ROOT / "web-qr.js"
EXTRAS = (ROOT / "web-extras.js").read_text(encoding="utf-8")
node = pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")
SAMPLES = ["A", "Hello", "สวัสดีครับ ขอบคุณ", "a" * 17, "b" * 53, "c" * 78, "ก" * 20, "d" * 120, "e" * 150, "f" * 200, "g" * 230, "h" * 271]


def _node(src):
    r = subprocess.run(["node", "-e", src], capture_output=True, text=True, timeout=60, cwd=ROOT)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def _encode(texts):
    js = "const q=require('./web-qr.js');const c=%s;console.log(JSON.stringify(c.map(t=>{const r=q.encode(t);return r&&{v:r.version,m:r.mask,s:r.size,d:r.modules.map(x=>x.map(b=>b?1:0))}})))" % json.dumps(texts)
    return _node(js)


def _bch_ok(word, gen):
    """Polynomdivision durch das Erzeugerpolynom: Rest 0 heißt gültiges BCH-Codewort."""
    glen = gen.bit_length()
    for i in range(word.bit_length() - glen, -1, -1):
        if word >> (i + glen - 1) & 1:
            word ^= gen << i
    return word == 0


@node
def test_sizes_versions_and_limit():
    out = _encode(["A", "a" * 17, "a" * 18, "a" * 271, "a" * 272])
    assert [(r["v"], r["s"]) if r else None for r in out] == [(1, 21), (1, 21), (2, 25), (10, 57), None]


@node
def test_function_patterns_timing_and_dark_module():
    for r in _encode(SAMPLES):
        m, n = r["d"], r["s"]
        for cx, cy in ((0, 0), (n - 7, 0), (0, n - 7)):                    # Suchmuster 7x7: Ring außen dunkel, Ring innen hell, Kern dunkel
            assert all(m[cy][cx + i] == m[cy + 6][cx + i] == m[cy + i][cx] == m[cy + i][cx + 6] == 1 for i in range(7))
            assert all(m[cy + 1][cx + i] == 0 for i in range(1, 6)) and all(m[cy + 2 + a][cx + 2 + b] == 1 for a in range(3) for b in range(3))
        for i in range(8, n - 8):                                            # Taktstreifen
            assert m[6][i] == m[i][6] == (1 if i % 2 == 0 else 0)
        assert m[n - 8][8] == 1                                              # festes dunkles Feld


@node
def test_format_information_is_valid_bch_and_matches_mask():
    for r in _encode(SAMPLES):
        m, n = r["d"], r["s"]
        first = [m[i][8] for i in range(6)] + [m[7][8], m[8][8], m[8][7]] + [m[8][14 - i] for i in range(9, 15)]
        bits = sum(b << i for i, b in enumerate(first)) ^ 0x5412
        assert _bch_ok(bits, 0x537) and bits >> 10 == 8 | r["m"]            # Stufe L = 01, dann die 3 Maskenbits
        second = [m[8][n - 1 - i] for i in range(8)] + [m[n - 15 + i][8] for i in range(8, 15)]
        assert sum(b << i for i, b in enumerate(second)) ^ 0x5412 == bits      # beide Kopien gleich


@node
def test_version_information_for_large_codes():
    for r in _encode(["x" * 150, "y" * 271]):
        m, n = r["d"], r["s"]
        bits = sum(m[i // 3][n - 11 + i % 3] << i for i in range(18))
        assert bits >> 12 == r["v"] and _bch_ok(bits, 0x1F25)
        assert bits == sum(m[n - 11 + i % 3][i // 3] << i for i in range(18))


@node
def test_deterministic_and_text_sensitive():
    a, b, c = _encode(["https://x.test/#pack=abc", "https://x.test/#pack=abc", "https://x.test/#pack=abd"])
    assert a == b and a["d"] != c["d"]


def test_decoder_roundtrip_when_available():
    """Gegenprobe mit einem unabhängigen Dekoder (zxing-cpp), wenn installiert; sonst übersprungen."""
    zx = pytest.importorskip("zxingcpp")
    np = pytest.importorskip("numpy")
    if not shutil.which("node"):
        pytest.skip("node nicht installiert")
    for text, r in zip(SAMPLES, _encode(SAMPLES)):
        img = np.pad(1 - np.array(r["d"], dtype=np.uint8), 4, constant_values=1) * 255
        img = np.kron(img, np.ones((6, 6), dtype=np.uint8)).astype(np.uint8)
        res = zx.read_barcodes(img)
        assert res and res[0].text == text, (len(text), r["v"])


def test_qr_source_has_no_library_network_or_unsafe_apis():
    js = QR.read_text(encoding="utf-8")
    assert "http://" not in js and "https://" not in js and "fetch(" not in js and "innerHTML" not in js and "eval(" not in js
    assert "(?<=" not in js and "(?<!" not in js          # kein Lookbehind: bricht ältere Safari-Versionen beim Laden
    assert QR.stat().st_size < 9000


def test_share_tab_wiring_and_texts():
    assert "qrCanvas(" in EXTRAS and "loadScript('web-qr.js')" in EXTRAS and "T.qrTooLong" in EXTRAS
    sw = (ROOT / "sw.js").read_text(encoding="utf-8")
    assert "'web-qr.js'" in sw
    for lg in ("de", "en", "th"):
        block = EXTRAS.split("var TXT25 = {", 1)[1].split("var NEGO", 1)[0]
        assert re.search(r"\n    " + lg + r": \{ audio: '[^']+', qrAlt: '[^']+', qrTooLong: '[^']+', qrHelp: '[^']+'", block), lg


@node
def test_share_link_fits_or_is_refused_cleanly():
    """packEncode begrenzt die Linklänge; alles Mögliche passt in 271 Bytes oder wird als „zu lang“ gemeldet (null)."""
    out = _node("const q=require('./web-qr.js');const l='https://example.org/en-th-dolmetscher/#pack='+'A'.repeat(300);console.log(JSON.stringify([q.encode(l),q.maxBytes]))")
    assert out == [None, 271]
