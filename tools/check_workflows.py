#!/usr/bin/env python3
"""Hausregeln fuer .github/workflows/*.yml (ohne Netz, nur Standardbibliothek; ergaenzt actionlint und zizmor).

  1. Jede fremde Action ist auf einen Commit (40 Hex-Zeichen) festgelegt und traegt dahinter "# vX.Y.Z".
  2. Jeder Job hat timeout-minutes (ein haengender Lauf blockiert sonst bis zum Limit von 6 Stunden).
  3. Jede Datei setzt "permissions:" auf oberster Ebene (Standard: nur lesen).
  4. Kein pull_request_target (Fork-Code mit Schreibrechten).
  5. Keine Auto-Deploys (deploy-pages, gh-pages, Veroeffentlichen auf Pages/Stores).

Aufruf:  python3 tools/check_workflows.py [Ordner]     (Exitcode 1 bei Befunden)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
USES_RE = re.compile(r"^\s*-?\s*uses:\s*(\S+)(?:\s+#\s*(.*))?$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
FORBIDDEN = ("pull_request_target", "deploy-pages", "gh-pages", "peaceiris/actions-gh-pages")


def jobs(lines):
    """{Jobname: [Zeilen]} aus dem Block 'jobs:' (Jobnamen stehen mit 2 Leerzeichen eingerueckt)."""
    out, cur, in_jobs = {}, None, False
    for line in lines:
        if re.match(r"^jobs:\s*$", line):
            in_jobs, cur = True, None
            continue
        if in_jobs and re.match(r"^\S", line) and line.strip():
            in_jobs, cur = False, None
        if not in_jobs:
            continue
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if m:
            cur = m.group(1)
            out[cur] = []
        elif cur is not None:
            out[cur].append(line)
    return out


def check_text(name, text):
    problems, lines = [], text.splitlines()
    if not re.search(r"^permissions:", text, re.M):
        problems.append(f"{name}: 'permissions:' auf oberster Ebene fehlt")
    for n, line in enumerate(lines, 1):
        code = line.split("#", 1)[0]
        for word in FORBIDDEN:
            if word in code:
                problems.append(f"{name}:{n}: '{word}' ist nicht erlaubt")
        m = USES_RE.match(line)
        if not m:
            continue
        target, comment = m.group(1), (m.group(2) or "").strip()
        if target.startswith(("./", "docker://")):
            continue
        ref = target.split("@", 1)[1] if "@" in target else ""
        if not SHA_RE.match(ref):
            problems.append(f"{name}:{n}: {target} ist nicht auf einen Commit festgelegt")
        elif not re.match(r"^v?\d+(\.\d+)*", comment):
            problems.append(f"{name}:{n}: hinter dem Commit fehlt der Versionskommentar (# v1.2.3)")
    for job, body in jobs(lines).items():
        block = "\n".join(body)
        if not re.search(r"^    timeout-minutes:", block, re.M) and not re.search(r"^    uses:", block, re.M):
            problems.append(f"{name}: Job '{job}' ohne timeout-minutes")
    return problems


def check_dir(folder=None):
    folder = pathlib.Path(folder) if folder else ROOT / ".github" / "workflows"
    problems = []
    for f in sorted(folder.glob("*.y*ml")):
        problems += check_text(f.name, f.read_text(encoding="utf-8"))
    return problems


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    problems = check_dir(argv[0] if argv else None)
    for p in problems:
        print("workflow:", p)
    if not problems:
        print("Workflows: Hausregeln eingehalten")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
