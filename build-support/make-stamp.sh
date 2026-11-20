#!/bin/bash
# make-stamp.sh LOCK – Stempel der Python-Umgebung: Lock-Hash, Python-Version (major.minor), Architektur.
# build.sh legt ihn als Contents/Resources/env-stamp ins Bundle; setup-env.sh kopiert ihn nach dem
# Einrichten nach venv/.dolmetscher-stamp. Die App startet die Engine nur, wenn beide gleich sind
# (anderer Lock nach einem App-Update -> Umgebung wird neu synchronisiert).
set -euo pipefail
LOCK="${1:?Nutzung: make-stamp.sh LOCK [PYTHON_VERSION] [ARCH]}"
# Python-Version und Architektur: Standard wie build.sh (3.12, arm64), per Argument oder Umgebung überschreibbar,
# damit der Stempel nicht von der tatsächlich gebauten Umgebung abweicht.
PYV="${2:-${DOLMETSCHER_STAMP_PYTHON:-3.12}}"
ARCH="${3:-${DOLMETSCHER_STAMP_ARCH:-arm64}}"
printf 'lock=%s\npython=%s\narch=%s\n' "$(shasum -a 256 "$LOCK" | cut -d' ' -f1)" "$PYV" "$ARCH"
