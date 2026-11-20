# ruff: noqa: E501
"""Neue reine Logik der Web-Seite (Zahlen, Karten, Allergien, Lernstand, Deep-Links) mit node; Eigenschaftstests."""
import json
import random
import re

import pytest

from _webhelpers import HAVE_NODE, HTML, ROOT, func, prelude, run

pytestmark = pytest.mark.skipif(not HAVE_NODE, reason="node nicht installiert")

DAY = 86_400_000
PRE = prelude(
    funcs=("scriptsDistinct", "scriptShare", "untranslated", "wrongScript", "unchanged", "implausible", "cutLen", "splitText",
           "thaiBelow", "thaiNumber", "thaiDigits", "parseAmount", "amountCard", "parseDeepLink", "presetOrder", "pbTransLoad",
           "myCardsParse", "allergyCard", "spreadDue", "learnMerge", "learnTsv", "localDay", "statsAdd", "statsSummary",
           "similarity", "reportUrl", "makeBackoff", "learnSide", "learnParse", "learnKey", "learnAdd", "parseShare"),
    lines=("const LEARN_KEY",),
) + "\n" + "\n".join(re.search(rf"^const {n}.*?;$", HTML.split("<script>")[1], re.S | re.M).group(0) for n in
                      ("TH_D", "PBT_MAX", "ISSUE_URL", "EMERGENCY")) + "\nconst MAX_SHARE = 500;"


def test_thai_numbers_table_and_roundtrip():
    cases = {0: "ศูนย์", 1: "หนึ่ง", 10: "สิบ", 11: "สิบเอ็ด", 20: "ยี่สิบ", 21: "ยี่สิบเอ็ด", 101: "หนึ่งร้อยเอ็ด",
             350: "สามร้อยห้าสิบ", 1000: "หนึ่งพัน", 2500: "สองพันห้าร้อย", 12345: "หนึ่งหมื่นสองพันสามร้อยสี่สิบห้า",
             1000000: "หนึ่งล้าน", 1500000: "หนึ่งล้านห้าแสน", 1000001: "หนึ่งล้านเอ็ด"}
    got = run(PRE, [f"thaiNumber({n})" for n in cases])
    assert got == list(cases.values())
    d = pytest.importorskip("dolmetscher")   # gleiche Logik wie die Engine: Zahlwort -> Ziffern
    nums = [25, 121, 350, 2500, 99999, 1500000, 100000]
    words = run(PRE, [f"thaiNumber({n})" for n in nums])
    for n, w in zip(nums, words):
        assert " ".join(d.thai_words_to_digits(w).split()) == str(n), (n, w)


def test_amount_helpers():
    got = run(PRE, ["parseAmount(' 3,50 ')", "parseAmount('abc')", "parseAmount('1234567890')", "amountCard(1500, '฿')",
                    "thaiDigits('350')", "thaiNumber(-3)", "thaiNumber(1e12)", "parseAmount('12.50')", "parseAmount('1,500')", "parseAmount('1.234,50')", "parseAmount('฿ 99.5')"])
    assert got == [4, None, None, "1,500 ฿\nหนึ่งพันห้าร้อยบาท", "๓๕๐", "", "", 13, 1500, 1235, 100]


def test_deep_links():
    ids = "['taxi','doctor']"
    got = run(PRE, [f"parseDeepLink('#preset=taxi&l=de', '', {ids})", f"parseDeepLink('#preset=evil', '', {ids})",
                    f"parseDeepLink('', '?text=%E0%B8%AA%E0%B8%A7%E0%B8%B1%E0%B8%AA', {ids})",
                    f"parseDeepLink('#preset=doctor&l=../x', '', {ids})", f"parseDeepLink('#x', '?text=' + 'a'.repeat(900), {ids}).incoming.length"])
    assert got == [{"preset": "taxi", "l": "de"}, {}, {"incoming": "สวัส"}, {"preset": "doctor"}, 500]


def test_preset_order_by_use():
    got = run(PRE, ["presetOrder(['a','b','c','d'], {c: 5, b: 5, d: 1})", "presetOrder(['a','b'], {})"])
    assert got == [["b", "c", "d", "a"], ["a", "b"]]


def test_pbtrans_load_migrates_expires_and_caps():
    now = 10 * 365 * DAY
    old = json.dumps({"th|a": "alt", "th|b": {"t": "neu", "ts": now - 5 * DAY}, "th|c": {"t": "verfallen", "ts": now - 91 * DAY},
                      "th|d": 5, "th|e": {"t": ""}})
    big = json.dumps({f"k{i}": {"t": "x", "ts": now - i} for i in range(1600)})
    got = run(PRE, [f"pbTransLoad({json.dumps(old)}, {now})", f"Object.keys(pbTransLoad({json.dumps(big)}, {now})).length",
                    "pbTransLoad('kaputt', 1)", f"'k0' in pbTransLoad({json.dumps(big)}, {now})", f"'k1599' in pbTransLoad({json.dumps(big)}, {now})"])
    assert got[0] == {"th|a": {"t": "alt", "ts": now}, "th|b": {"t": "neu", "ts": now - 5 * DAY}}
    assert got[1] == 1500 and got[2] == {} and got[3] is True and got[4] is False


def test_my_cards_parse():
    raw = json.dumps([{"label": " Hotel ", "text": "โรงแรม", "lang": "th"}, {"label": "", "text": "x", "lang": "th"},
                      {"label": "x", "text": "y", "lang": "__proto__"}, 5, {"label": "z", "text": "a" * 201, "lang": "th"}]
                     + [{"label": str(i), "text": "t", "lang": "de"} for i in range(40)])
    got = run(PRE, [f"myCardsParse({json.dumps(raw)}).length", f"myCardsParse({json.dumps(raw)})[0]", "myCardsParse('{')"])
    assert got == [30, {"label": "Hotel", "text": "โรงแรม", "lang": "th"}, []]


def test_allergy_card_uses_data_file():
    data = json.loads((ROOT / "allergens.json").read_text(encoding="utf-8"))
    for key in ("allergies", "conditions"):
        ids = [x["id"] for x in data[key]]
        assert len(ids) == len(set(ids)) and all(x["th"] and x["en"] and x["de"] for x in data[key])
    d = json.dumps(data)
    got = run(PRE, [f"allergyCard({{ids: ['egg','milk','peanut','insulin'], blood: 'AB', rh: 'บวก'}}, {d})",
                    f"allergyCard({{ids: ['fish']}}, {d})", f"allergyCard({{}}, {d})"])
    assert got[0] == {"th": "แพ้ไข่ นม และถั่วลิสง\nใช้อินซูลิน\nกรุ๊ปเลือด AB Rh บวก",
                      "en": "Allergic to eggs, milk and peanuts. I use insulin. Blood type AB+."}
    assert got[1]["th"] == "แพ้ปลา" and got[2] == {"th": "", "en": ""}


def test_learn_helpers():
    card = {"a": {"t": "Hallo", "l": "de"}, "b": {"t": "สวัสดี", "l": "th"}, "box": 1, "due": 0, "fav": True, "rec": False, "add": 0}
    cs = json.dumps(card)
    got = run(PRE, ["[0,9,10,11,25].map(i => spreadDue(i, 10, 1000))", f"learnMerge([{cs}], [{cs}, {{...{cs}, a: {{t: 'x', l: 'de'}}}}]).length",
                    f"learnTsv([{cs}])", "localDay(Date.UTC(2026, 5, 15, 12))",
                    "(() => { let s = {}; const n = Date.UTC(2026, 5, 15, 12); s = statsAdd(s, true, n); s = statsAdd(s, false, n);"
                    " s = statsAdd(s, true, n - DAY); return statsSummary(s, [{box: 5}, {box: 2}], n); })()",
                    "similarity('สวัสดี', 'สวัสดี')", "similarity('abc', 'xyz')", "similarity('Hello, World!', 'hello world')"])
    assert got[0] == [1000, 1000, 1000 + DAY, 1000 + DAY, 1000 + 2 * DAY]
    assert got[1] == 2 and got[2] == "Hallo\tสวัสดี\tde_th\n" and re.fullmatch(r"2026-06-1[45]", got[3])
    assert got[4]["today"] == 2 and got[4]["streak"] == 2 and got[4]["box5"] == 1 and got[4]["week"][5] == 1
    assert got[5] == 1 and got[6] == 0 and got[7] == 1


def test_backoff_and_unchanged():
    got = run(PRE, ["(() => { const b = makeBackoff(2, 1000); const r = [b.ok('g', 0)]; b.fail('g', 0); r.push(b.ok('g', 0)); b.fail('g', 0);"
                    " r.push(b.ok('g', 500)); r.push(b.ok('g', 1500)); b.fail('g', 2000); b.good('g'); b.fail('g', 2000); r.push(b.ok('g', 2001)); return r; })()",
                    "unchanged('This is a long sentence', 'this is a LONG sentence!')", "unchanged('Hi there', 'Hi there')",
                    "unchanged('This is a long sentence', 'Das ist ein langer Satz')"])
    assert got == [[True, True, False, True, True], True, False, False]


def test_emergency_numbers_and_report_url():
    got = run(PRE, ["Object.values(EMERGENCY).flat().map(x => x[1])", "Object.keys(EMERGENCY)",
                    "reportUrl({pack: 'taxi', en: 'Stop here', th: 'จอด', lang: 'th'})"])
    assert set(got[0]) <= {"1669", "1155", "191", "199"}
    ids = [p["id"] for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]]
    assert set(got[1]) <= set(ids)
    assert got[2].startswith("https://github.com/Pschmetzer/en-th-dolmetscher/issues/new?template=phrase-review.yml")
    assert (ROOT / ".github" / "ISSUE_TEMPLATE" / "phrase-review.yml").exists()


def test_manifest_shortcuts_and_share_target():
    m = json.loads((ROOT / "manifest.webmanifest").read_text(encoding="utf-8"))
    ids = {p["id"] for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]}
    assert m["shortcuts"] and all(s["url"] in ("./#numbers", "./#allergy") or (re.fullmatch(r"\./#preset=(\w+)", s["url"]) and s["url"].split("=")[1] in ids) for s in m["shortcuts"])
    assert m["share_target"]["method"] == "GET" and m["share_target"]["params"]["text"] == "text"
    sw = (ROOT / "sw.js").read_text(encoding="utf-8")
    for f in ("allergens.json", "presets-index.json"):
        assert f"'{f}'" in sw and (ROOT / f).exists()


def test_property_splittext_and_share_parse():
    rnd = random.Random(7)
    alphabets = ["กรุงเทพมหานครอมรรัตนโกสินทร์่้๊๋ั็", "abc def. ghi!", "😀👍🏽a b", "\u0000\u0007\n\t x"]
    cases = []
    for _ in range(60):
        a = rnd.choice(alphabets)
        cases.append(("".join(rnd.choice(a) for _ in range(rnd.randint(0, 900))), rnd.choice([30, 180, 300])))
    js = json.dumps(cases, ensure_ascii=False)
    out = run(PRE, [f"{js}.map(([t, m]) => {{ const p = splitText(t, m); return [p.every(x => x.length <= m), p.join('').replace(/\\s+/g, '') === t.replace(/\\s+/g, '')]; }})",
                    "['#show=' + 'x'.repeat(5000) + '&l=th', '#show=%00%1b&l=th', '#show=&l=th', '#l=th', '#show=a&l=__proto__']"
                    ".map(h => { const r = parseShare(h); return r === null || (r.text.length <= 500 && typeof r.lang === 'string'); })"])
    assert all(a and b for a, b in out[0]), [c for c, (a, b) in zip(cases, out[0]) if not (a and b)][:1]
    assert all(out[1])


def test_func_present():
    assert func("thaiNumber")
