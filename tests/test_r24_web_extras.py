# ruff: noqa: E501
"""Runde 24 (Web): web-extras.js (Preis, Verhandlung, Checkliste, Paket-Link, Töne, Mikro) und 23 neue Pakete."""
import json
import pathlib
import re
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
JS = ROOT / "web-extras.js"
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SW = (ROOT / "sw.js").read_text(encoding="utf-8")
node = pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")
NEW = ["camping-national-park", "night-bus-vip", "business-meeting", "contractor-renovation", "cave-waterfall-tour",
       "rock-climbing", "surf-kite-lesson", "herbal-traditional-medicine", "lab-blood-test", "meditation-retreat",
       "longtail-boat-charter", "utilities-condo-office", "used-vehicle-purchase", "vet-clinic", "school-enrollment",
       "electronics-mall", "print-copy-shop", "gold-shop", "notary-document-translation", "work-permit-office",
       "neighbors-noise-garbage", "orchard-farm-visit", "wildlife-safari"]


def _node(src):
    r = subprocess.run(["node", "-e", src], capture_output=True, text=True, timeout=60, cwd=ROOT)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


@node
def test_thai_numbers_and_offers():
    out = _node("const x=require('./web-extras.js');console.log(JSON.stringify([x.thaiNum(11),x.thaiNum(21),x.thaiNum(350),"
                "x.thaiNum(25000),x.thaiNum(-1),x.offers(300),x.convert(100,36,true),x.convert(1,0,true)]))")
    assert out[:5] == ["สิบเอ็ด", "ยี่สิบเอ็ด", "สามร้อยห้าสิบ", "สองหมื่นห้าพัน", ""]
    assert out[5] == [150, 200, 240] and abs(out[6] - 2.7778) < 1e-3 and out[7] is None


@node
def test_pack_link_roundtrip_and_limits():
    out = _node("""const x=require('./web-extras.js');(async()=>{
const t=await x.packEncode({n:'Tour',c:[['Hello','สวัสดี'],['<b>x</b>','น้ำ']]});
let tooBig=false; try{await x.packEncode({n:'z',c:Array.from({length:60},()=>[Array.from({length:12},()=>Math.random().toString(36).slice(2)).join(''),Array.from({length:12},()=>Math.random().toString(36).slice(2)).join('')])});}catch(e){tooBig=true}
console.log(JSON.stringify([await x.packDecode(t),await x.packDecode('!!'),await x.packDecode('A'.repeat(9000)),tooBig,x.cleanPack({c:[[1,2]]})]));})()""")
    assert out[0] == {"n": "Tour", "c": [["Hello", "สวัสดี"], ["<b>x</b>", "น้ำ"]]}
    assert out[1] is None and out[2] is None and out[3] is True and out[4] is None


def test_extras_never_use_innerhtml_or_upload():
    js = JS.read_text(encoding="utf-8")
    assert "innerHTML" not in js and "eval(" not in js and "document.write" not in js
    assert "sendBeacon" not in js and "XMLHttpRequest" not in js and "http://" not in js and "https://" not in js


def test_page_and_service_worker_wiring():
    assert 'id="btnTools"' in HTML and "web-extras.js" in HTML and "script-src 'self' 'unsafe-inline'" in HTML
    assert "'web-extras.js'" in SW
    assert "DolmetscherExtras" in JS.read_text(encoding="utf-8")


def test_extras_texts_in_three_languages():
    js = JS.read_text(encoding="utf-8")
    for lg in ("de", "en", "th"):
        assert re.search(r"\n    " + lg + r": \{ tools:", js), lg
        assert re.search(r"\n    " + lg + r": \['", js), lg


def test_tone_pairs_have_distinct_words():
    js = JS.read_text(encoding="utf-8")
    block = js.split("var PAIRS = [", 1)[1].split("var CHECK", 1)[0]
    words = re.findall(r"\['([^']+)', '[^']+', '[^']+'\]", block)
    assert len(words) == len(set(words)) >= 15
    for grp in re.findall(r"\n    \[(\[.*?\])\]", block):
        roms = re.findall(r"\['[^']+', '([^']+)', '[^']+'\]", grp)
        assert len(roms) == len(set(roms)), grp


@pytest.mark.parametrize("pid", NEW)
def test_new_pack_listed_and_indexed(pid):
    d = json.loads((ROOT / "presets" / f"{pid}.json").read_text(encoding="utf-8"))
    idx = {p["id"]: p for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]}
    assert len(d["phrases"]) >= 20 and sum(1 for p in d["phrases"] if p.get("critical")) >= 5
    assert idx[pid]["reviewed"] is False and f"'{pid}'" in HTML and f"'{pid}'" in SW
    assert d["style"] == "polite" and d["note"]["de"].endswith("nicht von Muttersprachlern geprüft.")


def test_pack_counts_in_docs():
    n = len(list((ROOT / "presets").glob("*.json")))
    assert n >= 201
    for f in ("README.md", "docs/ARCHITEKTUR.md", "llms.txt"):
        assert f"{n} " in (ROOT / f).read_text(encoding="utf-8"), f
