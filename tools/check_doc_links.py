#!/usr/bin/env python3
"""Prüft relative Links in den Markdown-Dateien (README, CONTRIBUTING, CHANGELOG, SECURITY, docs/**): zeigt jeder
Verweis auf eine vorhandene Datei bzw. einen vorhandenen Ordner? Ohne Netz, nur Standardbibliothek.

Aufruf:  python3 tools/check_doc_links.py        (Exitcode 1 bei toten Links)
Externe Links (http/https) prüft der Workflow docs-links.yml mit lychee, nicht dieses Skript.
Codeblöcke und Inline-Code werden übersprungen (dort stehen Beispiele, keine Links).
"""
import pathlib
import re
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOP = ("README.md", "CONTRIBUTING.md", "CHANGELOG.md", "SECURITY.md", "CODE_OF_CONDUCT.md")
LINK_RE = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)|!\[[^\]]*\]\(([^)\s]+)\)")
FENCE_RE = re.compile(r"^(```|~~~)")
INLINE_CODE_RE = re.compile(r"`[^`]*`")
SKIP_PREFIX = ("http://", "https://", "mailto:", "tel:", "#", "data:")


def md_files(root=ROOT):
    root = pathlib.Path(root)
    files = [root / n for n in TOP if (root / n).is_file()]
    files += sorted((root / "docs").rglob("*.md"))
    return files


def links_in(text):
    in_fence = False
    for no, line in enumerate(text.splitlines(), 1):
        if FENCE_RE.match(line.strip()):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for m in LINK_RE.finditer(INLINE_CODE_RE.sub("", line)):
            yield no, m.group(1) or m.group(2)


def dead_links(root=ROOT):
    """Liste (Datei, Zeile, Ziel) der Verweise ohne Ziel im Repository."""
    root = pathlib.Path(root)
    bad = []
    for f in md_files(root):
        for no, target in links_in(f.read_text(encoding="utf-8")):
            if target.startswith(SKIP_PREFIX):
                continue
            path = urllib.parse.unquote(target.split("#", 1)[0].split("?", 1)[0])
            if not path:
                continue
            dest = (root / path.lstrip("/")) if path.startswith("/") else (f.parent / path)
            if not dest.exists():
                bad.append((str(f.relative_to(root)), no, target))
    return bad


def main():
    bad = dead_links()
    for f, no, target in bad:
        print(f"{f}:{no}: toter Link -> {target}")
    if not bad:
        print(f"OK: keine toten relativen Links in {len(md_files())} Markdown-Dateien")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
