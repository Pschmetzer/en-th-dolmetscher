"""Runde 13: Oberflächentexte über alle Plattformen: Mac-App (de/en/th), iPhone (10 Sprachen) und Web (de/en/th).

Je Schlüssel und Sprache: vorhanden, nicht leer, gleiche Platzhalter (%@ %d %lld %f %1$@ und {name}) wie Englisch."""
import pathlib
import re

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS = ROOT / "ios" / "Dolmetscher"
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
LANGS3 = ("de", "en", "th")
IOS_LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\[|\]|:|,|//[^\n]*')
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:\.\d+)?(?:ll)?[@dfsu]|\{[A-Za-z_]+\}")
LETTER = {"th": "฀-๿", "ja": "぀-ヿ一-鿿", "ko": "가-힯ᄀ-ᇿ", "zh-Hans": "一-鿿",
          "ar": "؀-ۿ", "ru": "Ѐ-ӿ", "hi": "ऀ-ॿ"}


def _unescape(lit):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), lit[1:-1])


def swift_dict(src, name):
    """`static let NAME: [String: [String: String]] = [...]` -> verschachteltes dict (escape-bewusster Tokenizer)."""
    start = src.index(f"static let {name}:")
    body = src[src.index("[", src.index("=", start)):]
    toks = [t for t in TOKEN.findall(body) if not t.startswith("//")]
    pos = 0

    def value():
        nonlocal pos
        tok = toks[pos]
        if tok == "[":
            pos += 1
            out = {}
            while toks[pos] != "]":
                key = _unescape(toks[pos])
                assert toks[pos + 1] == ":", f"{name}: ':' fehlt nach {key!r}"
                pos += 2
                assert key not in out, f"{name}: Schlüssel {key!r} doppelt"
                out[key] = value()
                if toks[pos] == ",":
                    pos += 1
            pos += 1
            return out
        pos += 1
        return _unescape(tok)

    return value()


def ph(s):
    return sorted(PLACEHOLDER.findall(s))


# --- iPhone ----------------------------------------------------------------------------------------------

def _ios_tables():
    t = {"table": swift_dict((IOS / "L10n.swift").read_text(encoding="utf-8"), "table")}
    for n in (4, 5, 6, 7, 8, 9):
        f = IOS / f"L10n+R{n}.swift"
        t[f"round{n}"] = swift_dict(f.read_text(encoding="utf-8"), f"round{n}")
    return t


IOS_TABLES = _ios_tables()
IOS_EXTRA = swift_dict((IOS / "L10n+Extra.swift").read_text(encoding="utf-8"), "extra")


def test_ios_language_list_is_ten_and_has_lproj_folders():
    src = (IOS / "L10n.swift").read_text(encoding="utf-8")
    langs = tuple(re.findall(r'"([A-Za-z-]+)"', re.search(r"static let languages = \[([^\]]*)\]", src).group(1)))
    assert langs == IOS_LANGS
    for code in langs:
        if code != "en":                                # Englisch ist Entwicklungssprache (Base)
            assert (IOS / f"{code}.lproj" / "InfoPlist.strings").is_file(), code


@pytest.mark.parametrize("name", sorted(IOS_TABLES))
def test_ios_table_complete_nonempty_same_placeholders(name):
    problems = []
    for key, row in IOS_TABLES[name].items():
        if name == "table":                              # Grundtabelle: Rest steht in L10n.extra
            row = {**row, **{lg: IOS_EXTRA.get(lg, {}).get(key, "") for lg in IOS_LANGS if lg not in row}}
        for lg in IOS_LANGS:
            text = row.get(lg, "")
            if not text.strip():
                problems.append(f"{key}.{lg} fehlt/leer")
            elif ph(text) != ph(row["en"]):
                problems.append(f"{key}.{lg}: {ph(text)} != {ph(row['en'])}")
        stray = set(row) - set(IOS_LANGS)
        if stray:
            problems.append(f"{key}: unbekannte Sprachen {sorted(stray)}")
    assert not problems, problems[:20]


def test_ios_extra_covers_exactly_the_base_table_keys():
    assert set(IOS_EXTRA) == set(IOS_LANGS) - set(LANGS3)
    keys = set(IOS_TABLES["table"])
    for lg, rows in IOS_EXTRA.items():
        assert set(rows) == keys, (lg, sorted(set(rows) ^ keys)[:10])


def test_ios_keys_unique_across_tables():
    seen = {}
    for name, rows in IOS_TABLES.items():
        for key in rows:
            assert key not in seen, f"{key}: {seen[key]} und {name}"
            seen[key] = name


def test_ios_pack_names_extend_presets_only():
    rows = swift_dict((IOS / "L10n+R5.swift").read_text(encoding="utf-8"), "packNames")
    ids = {p.stem for p in (ROOT / "presets").glob("*.json")}
    assert set(rows) <= ids, sorted(set(rows) - ids)
    for key, row in rows.items():
        assert set(row) == set(IOS_LANGS) - set(LANGS3), (key, sorted(row))
        assert all(v.strip() for v in row.values()), key


def test_ios_texts_use_their_own_script():
    """th/ja/ko/zh-Hans-Texte ohne passende Schrift sind unübersetzt geblieben (außer wörtlich gleich wie en)."""
    bad = []
    for name, rows in IOS_TABLES.items():
        for key, row in rows.items():
            row = {**row, **{lg: IOS_EXTRA.get(lg, {}).get(key, "") for lg in IOS_LANGS if lg not in row}}
            for lg in ("th", "ja", "ko", "zh-Hans"):
                if row.get(lg) and row[lg] != row["en"] and not re.search(f"[{LETTER[lg]}]", row[lg]):
                    bad.append(f"{key}.{lg}")
    assert not bad, bad[:20]


# --- Mac-App ---------------------------------------------------------------------------------------------

def test_mac_table_placeholders_complete_and_nonempty():
    rows = swift_dict((ROOT / "app" / "L10n.swift").read_text(encoding="utf-8"), "table")
    assert len(rows) > 100
    bad = []
    for key, row in rows.items():
        if set(row) != set(LANGS3):
            bad.append(f"{key}: {sorted(row)}")
        elif not all(row[lg].strip() for lg in LANGS3):
            bad.append(f"{key}: leer")
        elif not (ph(row["de"]) == ph(row["en"]) == ph(row["th"])):
            bad.append(f"{key}: {[ph(row[lg]) for lg in LANGS3]}")
    assert not bad, bad[:20]


# --- Web -------------------------------------------------------------------------------------------------

def _web_str():
    from _webhelpers import web_str
    return web_str()


STR = _web_str()


def test_web_str_same_keys_nonempty_same_placeholders():
    assert tuple(STR) == LANGS3
    keys = set(STR["en"])
    for lg in LANGS3:
        assert set(STR[lg]) == keys, (lg, sorted(set(STR[lg]) ^ keys)[:10])
    bad = [f"{k}.{lg}" for k in keys for lg in LANGS3 if not STR[lg][k].strip()]
    assert not bad, bad
    bad = {k: [ph(STR[lg][k]) for lg in LANGS3] for k in keys if len({tuple(ph(STR[lg][k])) for lg in LANGS3}) > 1}
    assert not bad, bad


def test_web_thai_text_is_thai():
    bad = [k for k, v in STR["th"].items() if not re.search("[฀-๿]", v) and v != STR["en"][k]
           and re.search("[A-Za-z]{4}", re.sub(r"<[^>]+>|&\w+;|\{\w+\}", "", v))]
    assert not bad, bad


def _used_keys():
    keys = set(re.findall(r"\bt\('([A-Za-z0-9_]+)'", HTML))
    keys |= set(re.findall(r'data-i18n(?:-html)?="([A-Za-z0-9_]+)"', HTML))
    for m in re.finditer(r"\bt\((?:[^()']|'[^']*')*\?(?:[^()']|'[^']*')*\)", HTML):   # t(on ? 'a' : 'b')
        keys |= set(re.findall(r"'([A-Za-z0-9_]+)'", m.group(0)))
    block = HTML[HTML.index("const HARD_ERR = {"):]
    keys |= set(re.findall(r"'([A-Za-z0-9_]+)'", block[:block.index("};")].split("\n", 1)[1]))
    return keys


def test_web_every_used_key_exists_in_all_languages():
    used = _used_keys()
    assert len(used) > 100
    for lg in LANGS3:
        missing = sorted(k for k in used if k not in STR[lg])
        assert not missing, f"{lg}: {missing}"


def test_web_t_variables_are_present_in_every_language():
    bad = []
    for key, args in re.findall(r"\bt\('([A-Za-z0-9_]+)', \{([^{}]*)\}\)", HTML):
        names = re.findall(r"(?:^|,)\s*([A-Za-z_]\w*)\s*(?::|,|$)", args)
        for lg in LANGS3:
            bad += [f"{key}.{lg}: {{{n}}}" for n in names if key in STR[lg] and "{" + n + "}" not in STR[lg][key]]
    assert not bad, bad
