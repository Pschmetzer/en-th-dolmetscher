#!/usr/bin/env python3
"""Prueft die Form von CHANGELOG.md (ohne Netz, nur Standardbibliothek).

Regeln:
  - der erste Abschnitt ist "## Unreleased"
  - danach Versionen "## X.Y (Datum)" bzw. der Sammelabschnitt "## X.Y and earlier", absteigend sortiert
  - keine doppelten Versionen, keine leeren Abschnitte (Unreleased darf leer sein)
  - die neueste veroeffentlichte Version ist hoechstens die Version aus pyproject.toml
  - kein Tabulator, keine Leerzeichen am Zeilenende in Ueberschriften

Aufruf:  python3 tools/changelog_lint.py [--file CHANGELOG.md]    (Exitcode 1 bei Befunden)
"""
import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import changelog_extract as ce  # noqa: E402

ROOT = ce.ROOT
VERSION_RE = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?(?: \((\d{1,2} [A-Z][a-z]+ \d{4})\)| and earlier)?$")


def vtuple(s):
    m = VERSION_RE.match(s)
    return tuple(int(x or 0) for x in m.groups()[:3]) if m else None


def project_version(root=ROOT):
    text = (pathlib.Path(root) / "pyproject.toml").read_text(encoding="utf-8")
    m = re.search(r'^version\s*=\s*"([^"]+)"', text, re.M)
    return m.group(1) if m else None


def lint(text, pyproject_version=None):
    problems = []
    secs = ce.sections(text)
    if not secs:
        return ["keine Abschnitte (## ...) gefunden"]
    if secs[0][0].lower() != "unreleased":
        problems.append(f"erster Abschnitt muss 'Unreleased' sein, ist '{secs[0][0]}'")
    seen, last = set(), None
    for i, (name, body) in enumerate(secs):
        if i == 0 and name.lower() == "unreleased":
            continue
        if not VERSION_RE.match(name):
            problems.append(f"Ueberschrift '## {name}' passt nicht zu 'X.Y (Tag Monat Jahr)'")
            continue
        v = vtuple(name)
        if v in seen:
            problems.append(f"Version {name} doppelt")
        seen.add(v)
        if last is not None and v >= last:
            problems.append(f"Reihenfolge: {name} steht nach einer gleichen oder kleineren Version")
        last = v
        if not body.strip():
            problems.append(f"Abschnitt '{name}' ist leer")
    released = [vtuple(n) for n, _ in secs[1:] if vtuple(n)]
    if pyproject_version and released:
        pv = vtuple(pyproject_version)
        if pv and released[0] > pv:
            newest = ".".join(map(str, released[0]))
            problems.append(f"neueste Version im Changelog ({newest}) neuer als pyproject.toml ({pyproject_version})")
    for n, line in enumerate(text.splitlines(), 1):
        if line.startswith("#") and line != line.rstrip():
            problems.append(f"Zeile {n}: Leerzeichen am Ende einer Ueberschrift")
        if "\t" in line and not line.startswith(("    ", "\t")):
            problems.append(f"Zeile {n}: Tabulator")
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--file", default=str(ROOT / "CHANGELOG.md"))
    args = ap.parse_args(argv)
    problems = lint(pathlib.Path(args.file).read_text(encoding="utf-8"), project_version())
    for p in problems:
        print("CHANGELOG:", p)
    if not problems:
        print("CHANGELOG.md: Form in Ordnung")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
