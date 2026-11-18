"""Runde 13: docs/PROTOKOLL.md gegen Engine (dolmetscher.py) und Mac-App (app/Engine.swift).

Ergänzt tests/test_protocol_docs.py: dort wird "emit(...) -> Doku" geprüft; hier die Gegenrichtung (Doku nennt
nichts, was es nicht gibt), die Felder je Ereignis, die Liste CTRL_KEYS (control_ignored) und was die App sendet."""
import ast
import pathlib
import re

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")
SWIFT = (ROOT / "app" / "Engine.swift").read_text(encoding="utf-8")
TREE = ast.parse(SRC)
PY_MODULES = [p for p in ROOT.glob("*.py")]


def _events_table():
    body = DOCS[DOCS.index("## Ereignisse (stdout)"):DOCS.index("### `dropped.code`")]
    return {m.group(1): m.group(0) for m in re.finditer(r"^\| `([a-z_]+)` \|.*$", body, re.M)}


EVENT_ROWS = _events_table()


def _emit_calls():
    """(Ereignis, {Feldnamen}) aller emit("…", k=…)-Aufrufe in dolmetscher.py; **kw-Aufrufe zählen ohne Felder."""
    for node in ast.walk(TREE):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in ("emit", "_emit")
                and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str)):
            yield node.args[0].value, {k.arg for k in node.keywords if k.arg}


def _emitted_events():
    ev = {e for e, _ in _emit_calls()}
    ev |= set(re.findall(r'"event":\s*"([a-z_]+)"', SRC))                 # print(json.dumps({"event": …}))
    for m in PY_MODULES:                                                   # Hilfsmodule, die Ereignisse melden
        if m.name != "dolmetscher.py":
            ev |= set(re.findall(r'\bemit\(\s*"([a-z_]+)"', m.read_text(encoding="utf-8")))
    return ev


def test_documented_events_are_really_emitted():
    """Jede Zeile der Ereignis-Tabelle gehört zu einem Ereignis, das Engine oder App tatsächlich kennt."""
    assert len(EVENT_ROWS) > 30
    known = _emitted_events() | set(re.findall(r'case "([a-z_]+)"', SWIFT))
    ghost = sorted(set(EVENT_ROWS) - known)
    assert not ghost, f"in docs/PROTOKOLL.md, aber nirgends gesendet: {ghost}"


def test_mac_app_handles_only_documented_events():
    handler = SWIFT[SWIFT.index('case "loading":'):]
    handler = handler[:handler.index("func ", 1)] if "func " in handler[1:] else handler
    handled = set(re.findall(r'case "([a-z_]+)"(?:, "[a-z_]+")*:', handler))
    for line in re.findall(r'case ("[a-z_]+"(?:, "[a-z_]+")+):', handler):
        handled |= set(re.findall(r'"([a-z_]+)"', line))
    emitted = _emitted_events()
    assert handled and handled & emitted
    undocumented = sorted(e for e in handled if e not in EVENT_ROWS and e in emitted and f"`{e}`" not in DOCS)
    assert not undocumented, undocumented


def test_every_emit_keyword_field_is_documented():
    bad = []
    for ev, fields in _emit_calls():
        if ev not in EVENT_ROWS:
            continue
        for f in fields:
            if f"`{f}`" not in DOCS and f"{ev}.{f}" not in DOCS:
                bad.append(f"{ev}.{f}")
    assert not bad, sorted(set(bad))


def _apply_control_keys():
    fn = next(n for n in TREE.body if isinstance(n, ast.FunctionDef) and n.name == "apply_control")
    seg = ast.get_source_segment(SRC, fn)
    keys = set(re.findall(r'\bd\.get\("([a-z_]+)"', seg)) | set(re.findall(r'\bd\["([a-z_]+)"\]', seg))
    keys |= set(re.findall(r'"([a-z_]+)" in d\b', seg))
    keys |= set(re.findall(r'\b_(?:flag|choice|num|text)\w*\(d, "([a-z_]+)"', seg))
    return keys


def test_apply_control_reads_only_keys_that_control_ignored_accepts():
    """Liest apply_control ein Feld, das nicht in CTRL_KEYS steht, meldet die Engine es zugleich als unbekannt."""
    stray = sorted(k for k in _apply_control_keys() if k not in d.CTRL_KEYS
                   and not re.fullmatch(r"(tr|voice)_[a-z]{2}", k))
    assert not stray, stray


def test_every_control_key_is_documented():
    generic = {k for k in d.CTRL_KEYS if re.fullmatch(r"(tr|voice)_[a-z]{2}", k)}
    missing = sorted(k for k in d.CTRL_KEYS - generic if f"`{k}`" not in DOCS)
    assert not missing, f"CTRL_KEYS ohne Eintrag in docs/PROTOKOLL.md: {missing}"
    assert "`tr_<code>`" in DOCS and "`voice_<code>`" in DOCS                  # die Sprachtabellen-Familien


def test_mac_app_sends_only_known_control_keys():
    sent = set(re.findall(r'send\(\[\s*"([a-z_]+)"\s*:', SWIFT))
    for m in re.finditer(r'send\(\[([^\]]*)\]\)', SWIFT):
        sent |= set(re.findall(r'"([a-z_]+)"\s*:', m.group(1)))
    assert len(sent) > 20
    unknown = sorted(k for k in sent if k not in d.CTRL_KEYS and not re.fullmatch(r"(tr|voice)_[a-z]{2,}", k))
    assert not unknown, f"app/Engine.swift sendet Felder, die die Engine als unbekannt meldet: {unknown}"


def test_state_event_fields_documented():
    """`state` und `command`: alle Felder aus state_fields()/emit_snapshot() sind beschrieben."""
    seg = "".join(ast.get_source_segment(SRC, n) for n in ast.walk(TREE)
                  if isinstance(n, ast.FunctionDef) and n.name in ("state_fields", "emit_snapshot"))
    keys = set(re.findall(r'\b([a-z_]+)=', seg)) - {"cmd", "reply", "text"}
    assert {"mute", "earcons", "preset", "llm", "slow", "paused", "rate", "volume"} <= keys
    missing = sorted(k for k in keys if f"`{k}`" not in DOCS)
    assert not missing, missing
