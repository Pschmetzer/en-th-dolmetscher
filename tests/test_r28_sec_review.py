"""Sicherheits-Review R28: Kindprozesse bekommen nie API-Schlüssel/Passwort in der Umgebung."""
import ast
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def test_jeder_subprocess_aufruf_der_engine_filtert_die_umgebung():
    src = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
    bad = []
    for n in ast.walk(ast.parse(src)):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr in ("run", "Popen") \
                and isinstance(n.func.value, ast.Name) and n.func.value.id == "subprocess":
            kws = {k.arg for k in n.keywords}
            if "env" not in kws and None not in kws:     # None = **kw (Aufrufer setzt env per setdefault)
                bad.append(n.lineno)
    assert not bad, f"subprocess ohne env=_child_env() in Zeile {bad}"


def test_child_env_entfernt_geheimnisse():
    import dolmetscher as d
    env = d._child_env({"ANTHROPIC_API_KEY": "x", "ANTHROPIC_AUTH_TOKEN": "y", "DOLMETSCHER_HISTORY_PASSWORD": "z",
                        "PATH": "/usr/bin"})
    assert env == {"PATH": "/usr/bin"}


def test_log_ohne_log_text_enthaelt_keine_saetze():
    import dolmetscher as d
    old = d.LOG_TEXT
    d.LOG_TEXT = False
    try:
        out = d._redact_free(d._redact({"out": "geheimer Satz", "reply": "privat"}))
    finally:
        d.LOG_TEXT = old
    assert "geheimer" not in str(out) and "privat" not in str(out)
