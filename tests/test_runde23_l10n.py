"""Runde 23, Mac-App: app/L10n+R23.swift – jede Zeile hat de/en/th, Thai in thai, gleiche Platzhalter, keine doppelten
Schlüssel, und jeder Schlüssel wird mit L.r23()/L.r23f() auch benutzt (und jeder benutzte existiert)."""
import pathlib
import re

APP = pathlib.Path(__file__).resolve().parent.parent / "app"
SRC = (APP / "L10n+R23.swift").read_text(encoding="utf-8")
THAI = re.compile("[฀-๿]")
PLACEHOLDER = re.compile(r"%(?:\.\d+)?[@dfs]")


def rows():
    body = SRC[SRC.index("static let r23Table"):]
    out, dups = {}, []
    for m in re.finditer(r'"([a-z0-9_]+)":\s*\[((?:[^\[\]]|\[[^\]]*\])*?)\](?=,\s*(?:\n|"|\]))', body, re.S):
        key, inner = m.group(1), m.group(2)
        row = dict(re.findall(r'"(de|en|th)":\s*"((?:\\.|[^"\\])*)"', inner))
        if key in out:
            dups.append(key)
        out[key] = row
    return out, dups


def test_table_complete():
    table, dups = rows()
    assert len(table) > 30
    assert not dups, dups
    for k, r in table.items():
        assert set(r) == {"de", "en", "th"}, k
        assert all(v.strip() for v in r.values()), k
        assert THAI.search(r["th"]), k
        assert len({tuple(PLACEHOLDER.findall(v)) for v in r.values()}) == 1, k


def test_used_and_defined_keys_match():
    table, _ = rows()
    used = set()
    for f in APP.glob("*.swift"):
        used |= set(re.findall(r'\bL\.r23f?\(\s*"([a-z0-9_]+)"', f.read_text(encoding="utf-8")))
    assert not (used - set(table)), sorted(used - set(table))
    dynamic = set(re.findall(r'"(tip_[a-z]+)"', (APP / "ConversationUILogic.swift").read_text(encoding="utf-8")))
    assert not (set(table) - used - dynamic), sorted(set(table) - used - dynamic)
