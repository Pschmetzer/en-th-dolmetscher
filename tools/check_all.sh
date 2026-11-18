#!/usr/bin/env bash
# Lokale Pruefung wie die CI (ohne pre-commit): ruff, dann pytest ohne den Marker "macos".
# Aufruf: tools/check_all.sh [weitere pytest-Argumente]; mit PY=/pfad/zu/python anderes Python waehlen.
set -euo pipefail

cd "$(dirname "$0")/.."
PY="${PY:-python3}"

echo "== ruff =="
if command -v ruff >/dev/null 2>&1; then
  ruff check ./*.py bench/ tests/
else
  "$PY" -m ruff check ./*.py bench/ tests/
fi

echo "== pytest =="
"$PY" -m pytest -rs -m "not macos" "$@"

echo "OK: ruff und pytest gruen"
