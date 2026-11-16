#!/bin/bash
# make-stamp.sh LOCK – Stempel der Python-Umgebung: Lock-Hash, Python-Version (major.minor), Architektur.
# build.sh legt ihn als Contents/Resources/env-stamp ins Bundle; setup-env.sh kopiert ihn nach dem
# Einrichten nach venv/.dolmetscher-stamp. Die App startet die Engine nur, wenn beide gleich sind
# (anderer Lock nach einem App-Update -> Umgebung wird neu synchronisiert).
set -euo pipefail
LOCK="${1:?Nutzung: make-stamp.sh LOCK}"
printf 'lock=%s\npython=%s\narch=%s\n' "$(shasum -a 256 "$LOCK" | cut -d' ' -f1)" "3.12" "arm64"
