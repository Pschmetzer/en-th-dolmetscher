#!/usr/bin/env bash
# Lokale Pruefung wie die CI (ohne pre-commit): ruff, Skripte, Phrasenpakete, dann pytest ohne den Marker "macos".
# Aufruf: tools/check_all.sh [--docs] [weitere pytest-Argumente]; mit PY=/pfad/zu/python anderes Python waehlen.
#   --docs   nur die schnellen Doku- und Workflow-Pruefungen (Links, Landkarte, Changelog, Versionen, Workflows);
#            ohne ruff, Pakete und pytest: ideal vor einem Pull request, der nur docs/, CI oder tools/ beruehrt.
set -euo pipefail

cd "$(dirname "$0")/.."
PY="${PY:-python3}"

meta_checks() {
  echo "== Doku, Changelog, Versionen, Workflows =="
  "$PY" tools/check_doc_links.py
  "$PY" tools/check_docs_index.py
  "$PY" tools/changelog_lint.py
  "$PY" tools/check_version_sync.py
  "$PY" tools/check_workflows.py
}

if [ "${1:-}" = "--docs" ]; then
  meta_checks
  echo "OK: Doku-Pruefungen gruen"
  exit 0
fi

echo "== ruff =="
if command -v ruff >/dev/null 2>&1; then
  ruff check ./*.py bench/ tests/ tools/
else
  "$PY" -m ruff check ./*.py bench/ tests/ tools/
fi

echo "== Skripte (bash -n, shellcheck) =="
bash -n build.sh
for f in build-support/*.sh tools/*.sh; do bash -n "$f"; done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck build.sh build-support/*.sh tools/*.sh
else
  echo "shellcheck fehlt: uebersprungen (CI prueft es)"
fi
"$PY" -m py_compile app/make_icon.py

echo "== Phrasenpakete =="
"$PY" tools/make_presets_index.py --check || { echo "presets-index.json veraltet: python3 tools/make_presets_index.py"; exit 1; }
"$PY" tools/check_presets.py
"$PY" tools/sync_web.py --check || { echo "Web-Version veraltet: python3 tools/sync_web.py"; exit 1; }

meta_checks

echo "== pytest =="
"$PY" -m pytest -rs -m "not macos" "$@"

echo "OK: alle Pruefungen gruen"
