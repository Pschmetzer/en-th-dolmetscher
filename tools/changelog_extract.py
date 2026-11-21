#!/usr/bin/env python3
"""Zieht einen Abschnitt aus CHANGELOG.md, z. B. fuer die Release-Notes (Workflow release.yml).

Aufruf:
  python3 tools/changelog_extract.py 1.3            # Abschnitt "## 1.3 (...)" ohne die Ueberschrift
  python3 tools/changelog_extract.py v1.3           # fuehrendes v wird ignoriert
  python3 tools/changelog_extract.py Unreleased     # Abschnitt "## Unreleased"
  python3 tools/changelog_extract.py --list         # alle Abschnittsnamen

Exitcode 1, wenn der Abschnitt fehlt oder leer ist. Nur Standardbibliothek, ohne Netz.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
H2_RE = re.compile(r"^##\s+(.+?)\s*$")


def sections(text):
    """[(Name, Text)]: Name ist die Ueberschrift ohne '## ' (z. B. '1.3 (20 November 2026)')."""
    out, name, buf, in_fence = [], None, [], False
    for line in text.splitlines():
        if line.startswith(("```", "~~~")):
            in_fence = not in_fence
        m = None if in_fence else H2_RE.match(line)
        if m and not line.startswith("###"):
            if name is not None:
                out.append((name, "\n".join(buf).strip("\n")))
            name, buf = m.group(1), []
        elif name is not None:
            buf.append(line)
    if name is not None:
        out.append((name, "\n".join(buf).strip("\n")))
    return out


def normalize(version):
    return version.strip().lstrip("vV").strip().lower()


def extract(text, version):
    """Text des Abschnitts zu `version` oder None. 'Unreleased' passt unabhaengig von Gross-/Kleinschreibung."""
    want = normalize(version)
    for name, body in sections(text):
        head = name.split(" ", 1)[0].lower()
        if head == want or name.lower() == want:
            return body
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("version", nargs="?", help="Version (1.3, v1.3) oder Unreleased")
    ap.add_argument("--file", default=str(ROOT / "CHANGELOG.md"))
    ap.add_argument("--list", action="store_true", help="Abschnittsnamen ausgeben")
    args = ap.parse_args(argv)
    text = pathlib.Path(args.file).read_text(encoding="utf-8")
    if args.list:
        print("\n".join(n for n, _ in sections(text)))
        return 0
    if not args.version:
        ap.error("Version fehlt")
    body = extract(text, args.version)
    if not body or not body.strip():
        print(f"Kein (oder leerer) Abschnitt fuer '{args.version}' in {args.file}", file=sys.stderr)
        return 1
    print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
