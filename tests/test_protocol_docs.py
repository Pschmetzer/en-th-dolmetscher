"""docs/PROTOKOLL.md muss zum Code passen: Ereignisse, Startargumente (inkl. Standardwerte),
Steuerfelder und stabile Codes (dropped.code, error.code)."""
import ast
import pathlib
import re

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")
TREE = ast.parse(SRC)


def test_all_emitted_events_documented():
    events = set(re.findall(r'\bemit\(\s*"([a-z_]+)"', SRC))
    assert events, "no emit() calls found"
    missing = sorted(e for e in events if f"`{e}`" not in DOCS)
    assert not missing, f"Events missing in docs/PROTOKOLL.md: {missing}"


def _argparse_calls():
    for node in ast.walk(TREE):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == "add_argument" and node.args
                and isinstance(node.args[0], ast.Constant) and str(node.args[0].value).startswith("--")):
            yield node.args[0].value, {k.arg: k.value for k in node.keywords}


def _default(node):
    """Standardwert aus dem AST: Literal, Modulkonstante oder LLM["model"]."""
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.Name):
        return getattr(d, node.id)
    if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Name):
        return getattr(d, node.value.id)[ast.literal_eval(node.slice)]
    return None


def _row(opt):
    for line in DOCS.splitlines():
        first = line.split("|")[1] if line.startswith("|") and line.count("|") > 2 else ""
        if re.search(re.escape(f"`{opt}") + r"[`\s\\|]", first):
            return line
    return None


def test_all_start_arguments_documented_with_defaults():
    args = list(_argparse_calls())
    assert len(args) > 30
    missing = [o for o, _ in args if _row(o) is None]
    assert not missing, f"Startargumente fehlen in docs/PROTOKOLL.md: {missing}"
    wrong = []
    for opt, kw in args:
        if "default" not in kw:
            continue
        val = _default(kw["default"])
        if val in (None, False) or isinstance(val, bool):
            continue
        if f"`{val}`" not in _row(opt):
            wrong.append((opt, val))
    assert not wrong, f"Standardwert in docs/PROTOKOLL.md falsch/fehlt: {wrong}"


def test_silence_default_matches_docs():
    """Regression: Doku nannte 0.8, Code 0.7."""
    assert f"`{d.SILENCE_END}`" in _row("--silence")


def test_control_keys_documented():
    fn = next(n for n in TREE.body if isinstance(n, ast.FunctionDef) and n.name == "apply_control")
    seg = ast.get_source_segment(SRC, fn)
    keys = set(re.findall(r'\bd\.get\("([a-z_]+)"', seg)) | set(re.findall(r'\bd\["([a-z_]+)"\]', seg))
    keys |= set(re.findall(r'"([a-z_]+)" in d\b', seg)) | set(re.findall(r'_flag\(d, "([a-z_]+)"\)', seg))
    keys |= {f"voice_{k}" for k in ("en", "th")}           # f-String im Code
    assert {"say", "listen", "reassign", "ping"} <= keys
    missing = sorted(k for k in keys if f"`{k}`" not in DOCS)
    assert not missing, f"Steuerfelder fehlen in docs/PROTOKOLL.md: {missing}"


def test_drop_and_error_codes_documented():
    codes = {c for _, c in d._DROP_CODES} | {"other"}
    codes |= set(re.findall(r'\bcode="([a-z_]+)"', SRC))
    codes |= set(re.findall(r'return "([a-z_]+)", ', SRC))   # Mic._explain
    missing = sorted(c for c in codes if f"`{c}`" not in DOCS)
    assert not missing, f"Codes fehlen in docs/PROTOKOLL.md: {missing}"


def test_env_vars_documented():
    envs = set(re.findall(r'environ\.get\("(DOLMETSCHER_[A-Z_]+|ANTHROPIC_[A-Z_]+)"', SRC))
    envs |= set(re.findall(r'_find_tool\("[a-z]+", "([A-Z_]+)"\)', SRC))
    missing = sorted(e for e in envs if f"`{e}`" not in DOCS)
    assert not missing, f"Umgebungsvariablen fehlen in docs/PROTOKOLL.md: {missing}"
