"""app/L10n.swift: every UI string key needs de, en and th; every key used in the Swift sources must exist."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"
LANGS = ("de", "en", "th")
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\[|\]|:|,|//[^\n]*')
THAI = re.compile("[฀-๿]")
PLACEHOLDER = re.compile(r"%(?:\.\d+)?[@dfs]")


def _unescape(lit):
    s = lit[1:-1]
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def parse_table():
    """Returns (rows, duplicates): rows = {key: {lang: text}}, parsed with an escape-aware tokenizer."""
    src = (APP / "L10n.swift").read_text(encoding="utf-8")
    start = src.index("static let table")
    body = src[src.index("[", src.index("=", start)):]
    toks = [t for t in TOKEN.findall(body) if not t.startswith("//")]
    assert toks[0] == "[", toks[:5]
    i, rows, dups = 1, {}, []
    while i < len(toks) and toks[i] != "]":
        key = _unescape(toks[i])
        assert toks[i + 1] == ":" and toks[i + 2] == "[", f"unexpected tokens near {key!r}"
        i += 3
        row = {}
        while toks[i] != "]":
            lang = _unescape(toks[i])
            assert toks[i + 1] == ":", f"{key}: expected ':' after {lang!r}"
            assert toks[i + 2].startswith('"'), f"{key}.{lang}: value is not a string literal"
            assert lang not in row, f"{key}: language {lang} twice"
            row[lang] = _unescape(toks[i + 2])
            i += 3
            if toks[i] == ",":
                i += 1
        i += 1  # closing ]
        if toks[i] == ",":
            i += 1
        if key in rows:
            dups.append(key)
        rows[key] = row
    return rows, dups


def used_keys():
    keys = set()
    for f in APP.glob("*.swift"):
        if f.name == "L10n.swift":
            continue
        keys |= set(re.findall(r'\bL\.[tf]\(\s*"([A-Za-z0-9_]+)"\s*[,)]', f.read_text(encoding="utf-8")))
    return keys


def test_no_duplicate_keys():
    # A duplicate key in a Swift dictionary literal crashes at runtime.
    _, dups = parse_table()
    assert not dups, f"Duplicate keys in L10n.swift: {dups}"


def test_every_key_has_all_languages():
    rows, _ = parse_table()
    assert len(rows) > 100
    bad = {k: sorted(set(LANGS) - {lg for lg, v in r.items() if v.strip()}) for k, r in rows.items()
           if not all(r.get(lg, "").strip() for lg in LANGS)}
    assert not bad, f"Keys with a missing or empty language: {bad}"
    extra = {k: sorted(set(r) - set(LANGS)) for k, r in rows.items() if set(r) - set(LANGS)}
    assert not extra, f"Unknown language codes: {extra}"


def test_thai_text_is_thai():
    rows, _ = parse_table()
    bad = [k for k, r in rows.items() if not THAI.search(r["th"]) and r["th"] != r["en"]]
    assert not bad, f"th text without Thai script that also differs from en (untranslated?): {bad}"


def test_placeholders_match_across_languages():
    rows, _ = parse_table()
    bad = {k: [PLACEHOLDER.findall(r[lg]) for lg in LANGS] for k, r in rows.items()
           if len({tuple(PLACEHOLDER.findall(r[lg])) for lg in LANGS}) > 1}
    assert not bad, f"Format placeholders differ between languages: {bad}"


def test_used_keys_exist():
    rows, _ = parse_table()
    missing = sorted(used_keys() - set(rows))
    assert not missing, f"L.t()/L.f() keys missing from the table: {missing}"


def test_no_unused_keys():
    rows, _ = parse_table()
    src = "\n".join(f.read_text(encoding="utf-8") for f in APP.glob("*.swift") if f.name != "L10n.swift")
    literals = set(re.findall(r'"([A-Za-z0-9_]+)"', src))
    dynamic_prefixes = ("style_",)   # L.t("style_" + name)
    unused = sorted(k for k in rows if k not in literals and not k.startswith(dynamic_prefixes))
    assert not unused, f"Unused L10n keys (remove or use): {unused}"
