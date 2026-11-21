#!/usr/bin/env python3
"""Pruefung: Versionsangaben in pyproject.toml, docs/VERSIONEN.md und CHANGELOG.md passen zusammen.

  - docs/VERSIONEN.md nennt als Stand der Mac-App und Engine die Version aus pyproject.toml
  - CHANGELOG.md hat keinen Abschnitt, der neuer ist als pyproject.toml (changelog_lint.py prueft die Form)
  - ein Git-Tag v<Version> (falls Argument --tag gegeben) entspricht pyproject.toml

Aufruf:  python3 tools/check_version_sync.py [--tag v1.3]     (Exitcode 1 bei Abweichung)
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def pyproject_version(root=ROOT):
    text = (pathlib.Path(root) / "pyproject.toml").read_text(encoding="utf-8")
    m = re.search(r'^version\s*=\s*"([^"]+)"', text, re.M)
    return m.group(1) if m else None


def doc_version(root=ROOT):
    """Stand der Zeile 'Mac-App und Engine' in docs/VERSIONEN.md (letzte Tabellenspalte)."""
    text = (pathlib.Path(root) / "docs" / "VERSIONEN.md").read_text(encoding="utf-8")
    m = re.search(r"^\|\s*Mac-App und Engine\s*\|[^|]*\|\s*([^|\s]+)\s*\|", text, re.M)
    return m.group(1) if m else None


def check(root=ROOT, tag=None):
    problems = []
    py = pyproject_version(root)
    if not py:
        return ["pyproject.toml: keine version gefunden"]
    doc = doc_version(root)
    if doc != py:
        problems.append(f"docs/VERSIONEN.md nennt {doc!r}, pyproject.toml {py!r}")
    if tag is not None and tag.lstrip("v") != py:
        problems.append(f"Tag {tag} passt nicht zu pyproject.toml ({py})")
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--tag", help="Tag-Name pruefen, z. B. v1.3")
    args = ap.parse_args(argv)
    problems = check(tag=args.tag)
    for p in problems:
        print("version:", p)
    if not problems:
        print(f"Versionen stimmen ueberein ({pyproject_version()})")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
