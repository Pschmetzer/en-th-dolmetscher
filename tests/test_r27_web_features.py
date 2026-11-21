# ruff: noqa: E501
"""Runde 27 (Web): Verlauf-Tags, Checkliste exportieren, Mehrfach-QR fuer lange Karten-Links, Lighthouse-CI, E2E-Ablauf."""
import json
import pathlib
import shutil
import subprocess

import pytest

from _webhelpers import HAVE_NODE, SCRIPT, func, prelude, run

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXTRAS = (ROOT / "web-extras.js").read_text(encoding="utf-8")
node = pytest.mark.skipif(not HAVE_NODE or not shutil.which("node"), reason="node nicht installiert")


def _node(src):
    r = subprocess.run(["node", "-e", src], capture_output=True, text=True, timeout=60, cwd=ROOT)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


@node
def test_csv_gets_a_tag_column_only_when_entries_are_tagged():
    pre = prelude(funcs=["logCsv"])
    got = run(pre, ["logCsv([{ orig: 'hi', trans: 'x', g: '⭐' }])", "logCsv([{ orig: 'hi', trans: 'x', g: '' }])"])
    assert got[0] == '"original","translation","tag"\r\n"hi","x","⭐"\r\n'
    assert got[1] == '"original","translation"\r\n"hi","x"\r\n'


def test_history_tags_are_wired_into_the_existing_log():
    add, rows, txt = func("addEntry"), func("logRows"), func("logText")
    assert "tagb" in add and "tagEntry(entry, '')" in add
    assert "g: e.dataset.g" in rows and "e.dataset.g" in txt and "e.dataset.g" in func("logSearchText")
    assert "const LOG_TAGS = ['', '⭐'" in SCRIPT and "log.addEventListener('click'" in SCRIPT
    assert "sessionStorage" not in func("tagEntry") and "localStorage" not in func("tagEntry")    # Tags bleiben im Verlauf der Sitzung


@node
def test_checklist_text_marks_done_items():
    out = _node("const x=require('./web-extras.js');console.log(JSON.stringify([x.checklistText('T',['a','b','c'],{0:true,2:true}), x.checklistText('T',['a'],null)]))")
    assert out[0] == "T\n\n[x] a\n[ ] b\n[x] c\n" and out[1] == "T\n\n[ ] a\n"
    assert "download: 'reise-checkliste.txt'" in EXTRAS and "T.ckExport" in EXTRAS
    assert all(k in EXTRAS for k in ("ckExport:", "ckTitle:"))


@node
def test_long_link_is_split_into_qr_parts_that_reassemble():
    out = _node("""
const x=require('./web-extras.js'), q=require('./web-qr.js'); const base='https://pschmetzer.github.io/en-th-dolmetscher/';
const frag=Array.from({length:1900},(_, i)=>'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'[(i*7)%64]).join('');
const parts=x.qrParts(base,frag,q.maxBytes); const enc=parts.map(u=>q.encode(u));
let st=null,r; for(const u of parts.slice().reverse()){ r=x.partAdd(st,x.partParse(new URL(u).hash)); st=r.st; }
const bad=x.partAdd(null,{i:1,n:2,id:'zzzz',d:'AA'}); const bad2=x.partAdd(bad.st,{i:2,n:2,id:'zzzz',d:'BB'});
console.log(JSON.stringify({n:parts.length, fits:enc.every(Boolean), ok:r.done&&r.frag===frag, maxLen:Math.max(...parts.map(p=>Buffer.byteLength(p))), short:x.qrParts(base,'abc',q.maxBytes)&&x.qrParts(base,'abc',q.maxBytes).length, tooMany:x.qrParts(base,'A'.repeat(4000),q.maxBytes), bad:bad2.bad===true&&bad2.done===false, p:[x.partParse('#part=1.3.abcd.xyz'),x.partParse('#part=4.3.abcd.xyz'),x.partParse('#part=1.1.abcd.xyz'),x.partParse('#pack=abc'),x.partParse('#part=1.2.ABCD.x')]}))""")
    assert 2 <= out["n"] <= 12 and out["fits"] and out["ok"] and out["maxLen"] <= 271
    assert out["short"] == 2 and out["tooMany"] is None and out["bad"]
    assert out["p"][0] == {"i": 1, "n": 3, "id": "abcd", "d": "xyz"} and out["p"][1:] == [None, None, None, None]


@node
def test_typical_card_packs_up_to_about_two_kilobytes_fit_in_a_few_qr_codes():
    out = _node("""
const x=require('./web-extras.js'), q=require('./web-qr.js'), fs=require('fs');
(async()=>{ const d=JSON.parse(fs.readFileSync('presets/snake-bite-venomous.json','utf8')); const res=[];
for (const n of [3,8,16,24]) { const t=await x.packEncode({n:'Test',c:d.phrases.slice(0,n).map(p=>[p.en,p.th])});
  const link='https://pschmetzer.github.io/en-th-dolmetscher/#pack='+t; const one=!!q.encode(link); const parts=x.qrParts('https://pschmetzer.github.io/en-th-dolmetscher/',t,q.maxBytes);
  res.push({n, len:link.length, one, parts:parts&&parts.length}); }
console.log(JSON.stringify(res)); })()""")
    by = {r["n"]: r for r in out}
    assert by[24]["len"] < 2048 and all(r["one"] or (r["parts"] and r["parts"] <= 12) for r in out)    # bis rund 2 KB: ein Code oder mehrere
    assert by[8]["parts"] and by[8]["parts"] > 1                                                        # 8 Karten brauchen mehrere Codes


def test_share_and_import_wiring_for_parts():
    assert "await qrMany(qrBox, t, T)" in EXTRAS and "partParse(location.hash" in EXTRAS and "store('parts'" in EXTRAS
    assert "/^#(pack|part)=/.test(location.hash)" in SCRIPT
    for lg in ("de", "en", "th"):
        i = EXTRAS.index("var TXT27")
        assert " %s: {" % lg in EXTRAS[i:i + 3000]
    assert "qrParts" in EXTRAS and "MAX_PARTS = 12" in EXTRAS


def test_lighthouse_ci_is_configured_and_not_blocking():
    wf = (ROOT / ".github" / "workflows" / "lighthouse.yml").read_text(encoding="utf-8")
    assert "continue-on-error: true" in wf and "http.server" in wf and ".github/lighthouse/lighthouserc.json" in wf and "pull_request" in wf
    assert "permissions:\n  contents: read" in wf and "persist-credentials: false" in wf
    rc = json.loads((ROOT / ".github" / "lighthouse" / "lighthouserc.json").read_text(encoding="utf-8"))
    col, asr = rc["ci"]["collect"], rc["ci"]["assert"]["assertions"]
    assert col["url"][0].startswith("http://localhost:8000/") and col["numberOfRuns"] >= 1
    assert asr["categories:performance"][1]["minScore"] > 0 and asr["categories:accessibility"][1]["minScore"] >= 0.9
    assert all(v == "off" or v[0] in ("warn", "error") for v in asr.values())
    assert "total-byte-weight" in asr and "largest-contentful-paint" in asr


def test_playwright_e2e_flow_and_ci_job():
    e2e = (ROOT / "tests" / "web-e2e" / "flow.mjs").read_text(encoding="utf-8")
    for needle in ("presetSel", "serviceWorker", "setOffline", "offline", "pbQ", "pageerror"):
        assert needle in e2e, needle
    pkg = json.loads((ROOT / "tests" / "web-e2e" / "package.json").read_text(encoding="utf-8"))
    assert "playwright" in pkg["dependencies"]
    wf = (ROOT / ".github" / "workflows" / "web-a11y.yml").read_text(encoding="utf-8")
    assert "node flow.mjs" in wf and "e2e:" in wf and "workflow_dispatch" in wf
