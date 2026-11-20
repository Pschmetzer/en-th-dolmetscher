#!/usr/bin/env bash
# Lokale Pruefung wie die CI (ohne pre-commit): ruff, Skripte, Phrasenpakete, dann pytest ohne den Marker "macos".
# Aufruf: tools/check_all.sh [weitere pytest-Argumente]; mit PY=/pfad/zu/python anderes Python waehlen.
set -euo pipefail

cd "$(dirname "$0")/.."
PY="${PY:-python3}"

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
  shellcheck build.sh build-support/*.sh
else
  echo "shellcheck fehlt: uebersprungen (CI prueft es)"
fi
"$PY" -m py_compile app/make_icon.py

echo "== Phrasenpakete =="
"$PY" tools/make_presets_index.py --check || { echo "presets-index.json veraltet: python3 tools/make_presets_index.py"; exit 1; }
"$PY" tools/check_presets.py

echo "== pytest =="
"$PY" -m pytest -rs -m "not macos" "$@"

echo "OK: alle Pruefungen gruen"
