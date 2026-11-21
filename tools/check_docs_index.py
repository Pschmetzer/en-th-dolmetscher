#!/usr/bin/env python3
"""Pruefung: docs/README.md (die Doku-Landkarte) verlinkt jede Markdown-Datei in docs/ (auch in Unterordnern),
und jeder Link dort zeigt auf eine vorhandene Datei. So bleibt neue Doku auffindbar.

Aufruf:  python3 tools/check_docs_index.py     (Exitcode 1 bei Befunden; ohne Netz, nur Standardbibliothek)
"""
import pathlib
import re
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
LINK_RE = re.compile(r"\]\(([^)\s#]+)(?:#[^)\s]*)?\)")


def linked_files(index_path):
    """Menge der Dateien (aufgeloest, relativ zu docs/), auf die die Landkarte verweist."""
    base = index_path.parent
    text = index_path.read_text(encoding="utf-8")
    out = set()
    for target in LINK_RE.findall(text):
        if target.startswith(("http://", "https://", "mailto:")):
            continue
        out.add((base / urllib.parse.unquote(target)).resolve())
    return out


def check(root=ROOT):
    root = pathlib.Path(root)
    docs = root / "docs"
    index = docs / "README.md"
    if not index.is_file():
        return ["docs/README.md fehlt"]
    linked = linked_files(index)
    problems = []
    for md in sorted(docs.rglob("*.md")):
        if md.resolve() == index.resolve():
            continue
        # Unterordner mit eigener README (th/, store/ ...): die README muss verlinkt sein, der Rest nicht.
        if md.parent != docs and (md.parent / "README.md").is_file() and md.name != "README.md":
            continue
        if md.resolve() not in linked:
            problems.append(f"{md.relative_to(root)} fehlt in docs/README.md")
    for target in sorted(linked):
        if not target.exists():
            problems.append(f"docs/README.md verweist auf fehlende Datei {target.name}")
    return problems


def main():
    problems = check()
    for p in problems:
        print("docs-index:", p)
    if not problems:
        print("docs/README.md: alle Dokumente verlinkt")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
