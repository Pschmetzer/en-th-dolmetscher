#!/bin/bash
# setup-env.sh – richtet die Python-Umgebung der App ein (Erststart, nach App-Update, „neu einrichten“).
#   setup-env.sh UV LOCK STAMP SUPPORT
#     UV       mitgeliefertes uv (Contents/Helpers/uv)
#     LOCK     requirements.txt mit Hashes (Contents/Resources)
#     STAMP    erwarteter Stempel (Contents/Resources/env-stamp: Lock-Hash, Python-Version, Architektur)
#     SUPPORT  ~/Library/Application Support/Dolmetscher
# Legt SUPPORT/venv mit einem uv-verwalteten Python (SUPPORT/python) an und installiert den Lock
# exakt (uv pip sync, nur Wheels, Hash-Prüfung). Der Stempel SUPPORT/venv/.dolmetscher-stamp wird
# als Letztes geschrieben: fehlt er oder weicht er ab, gilt die Umgebung als nicht eingerichtet.
# Fasst nur SUPPORT an (nie ein per DOLMETSCHER_PYTHON gesetztes Python). Läuft auch unter `env -i`.
# Ausgabe (stdout, eine Zeile je Ereignis, für die App):
#   step python|packages|verify   – Schritt beginnt
#   progress N                    – Fortschritt der Paketinstallation in Prozent (geschätzt)
#   done                          – fertig, Stempel geschrieben
#   fail offline|disk|integrity|arch|failed – abgebrochen (Details in SUPPORT/setup.log)
set -uo pipefail
[ $# -eq 4 ] || { echo "Nutzung: $0 UV LOCK STAMP SUPPORT" >&2; exit 2; }
UV="$1"; LOCK="$2"; STAMP="$3"; SUPPORT="$4"
VENV="$SUPPORT/venv"
LOG="$SUPPORT/setup.log"
PY_VERSION="$(sed -n 's/^python=//p' "$STAMP" 2>/dev/null)"
PY_VERSION="${PY_VERSION:-3.12}"

mkdir -p "$SUPPORT" || { echo "fail disk"; exit 1; }
: > "$LOG"
export UV_PYTHON_INSTALL_DIR="$SUPPORT/python"   # Python gehört der App, nicht ~/.local/share/uv
export UV_CACHE_DIR="$SUPPORT/uv-cache"
export UV_NO_CONFIG=1                            # keine uv.toml/pyproject des Nutzers
export UV_PYTHON_PREFERENCE=only-managed         # nie Homebrew/conda/System-Python
export UV_PYTHON_DOWNLOADS=automatic
export UV_NO_PROGRESS=1
export UV_LINK_MODE=clone                        # APFS: Kopie ohne Platzbedarf, Cache danach löschbar
export UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-60}"
unset VIRTUAL_ENV PYTHONPATH PYTHONHOME

CHILD=""
TICK=""
cleanup_partial() { rm -rf "$VENV" "$UV_CACHE_DIR"; }
on_term() {
  [ -n "$TICK" ] && kill "$TICK" 2>/dev/null
  [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null && wait "$CHILD" 2>/dev/null
  cleanup_partial
  echo "fail cancelled"
  exit 130
}
trap on_term TERM INT HUP
trap '' PIPE                                     # App weg (stdout zu): nicht mitten im Schritt sterben

# Kindprozess im Hintergrund + wait: so wirkt Abbrechen (SIGTERM) sofort.
run() { "$@" >>"$LOG" 2>&1 & CHILD=$!; wait "$CHILD"; local rc=$?; CHILD=""; return $rc; }

fail() {   # Fehlerart aus dem Log erraten, Teil-Umgebung entfernen
  local kind=failed      # integrity vor offline: ein Hash-Fehler ist kein Netzproblem (Wiederholen hilft nicht)
  if grep -qiE "no space left|ENOSPC|disk full" "$LOG"; then kind=disk
  elif grep -qiE "hash mismatch|checksum|hashes? do(es)? not match|digest mismatch" "$LOG"; then kind=integrity
  elif grep -qiE "dns|resolve|network|connect(ion)? (refused|reset|error|failed)|timed out|timeout|offline|unreachable|tls|certificate|failed to fetch|failed to download|request failed" "$LOG"; then kind=offline
  fi
  cleanup_partial
  echo "fail $kind"
  exit 1
}

[ "$(uname -m)" = arm64 ] || { echo "nur Apple Silicon (arm64), gefunden: $(uname -m)" >>"$LOG"; echo "fail arch"; exit 1; }
[ -x "$UV" ] || { echo "uv fehlt: $UV" >>"$LOG"; echo "fail failed"; exit 1; }
[ -f "$LOCK" ] && [ -f "$STAMP" ] || { echo "Lock/Stempel fehlt" >>"$LOG"; echo "fail failed"; exit 1; }

# Nr. 22: Update einer App-eigenen venv desselben Python/derselben Architektur: nur die Differenz des Locks
# installieren (uv pip sync) statt alles neu zu laden; scheitert das, folgt der vollständige Neuaufbau.
REUSE=0
if [ -x "$VENV/bin/python" ] && [ -f "$VENV/.dolmetscher-stamp" ] && [ -f "$VENV/pyvenv.cfg" ] \
   && grep -q "^home = $SUPPORT/python/" "$VENV/pyvenv.cfg"; then
  [ "$(grep -v '^lock=' "$VENV/.dolmetscher-stamp")" = "$(grep -v '^lock=' "$STAMP")" ] && REUSE=1
fi
rm -f "$VENV/.dolmetscher-stamp"
# Eine venv, die nicht auf das App-eigene Python zeigt (z. B. von build.sh mit conda/Homebrew-Python angelegt),
# wird nie gelöscht, sondern beiseitegelegt (venv.vorher-DATUM) – nur App-eigene venvs werden neu aufgebaut.
if [ -f "$VENV/pyvenv.cfg" ] && ! grep -q "^home = $SUPPORT/python/" "$VENV/pyvenv.cfg"; then
  KEEP="$SUPPORT/venv.vorher-$(date +%Y%m%d-%H%M%S)"
  mv "$VENV" "$KEEP" || { echo "fremde venv nicht verschiebbar: $VENV" >>"$LOG"; echo "fail failed"; exit 1; }
  echo "fremde venv beiseitegelegt: $KEEP" >>"$LOG"
fi
# Nr. 50: mitgelieferte Wheels (build.sh --bundle-wheels) neben dem Lock: dann ohne Netz installieren.
WHEELS="$(dirname "$LOCK")/offline/wheels"
sync_packages() {
  # Nr. 23: Fortschritt (0-99) aus dem Wachstum des Download-Caches schätzen (~450 MB), alle 2 s eine Zeile
  ( while :; do
      sleep 2
      kb="$(du -sk "$UV_CACHE_DIR" 2>/dev/null | awk '{print $1}')"
      pct=$(( ${kb:-0} / 4500 )); [ "$pct" -gt 99 ] && pct=99
      [ "$pct" -gt 0 ] && echo "progress $pct"
    done ) &
  TICK=$!
  local rc=0
  if [ -d "$WHEELS" ]; then
    run "$UV" pip sync --quiet --require-hashes --no-build --offline --find-links "$WHEELS" --python "$VENV/bin/python" "$LOCK" || rc=1
  else
    run "$UV" pip sync --quiet --require-hashes --no-build --python "$VENV/bin/python" "$LOCK" || rc=1
  fi
  kill "$TICK" 2>/dev/null; wait "$TICK" 2>/dev/null; TICK=""
  return $rc
}

echo "step python"
if [ "$REUSE" = 1 ]; then
  echo "vorhandene venv wird aktualisiert (nur Differenz)" >>"$LOG"
  echo "step packages"
  if ! sync_packages; then
    echo "Aktualisierung fehlgeschlagen, baue die Umgebung neu auf" >>"$LOG"
    REUSE=0
  fi
fi
if [ "$REUSE" != 1 ]; then
  run "$UV" venv --clear --quiet --python "$PY_VERSION" "$VENV" || fail
  echo "step packages"
  sync_packages || fail
fi

echo "step verify"
run "$VENV/bin/python" -B -c 'import sys, faster_whisper, av, ctranslate2, numpy; print(sys.version)' || fail

rm -rf "$UV_CACHE_DIR"                              # ~400 MB Download-Cache: nach dem Klonen unnötig
cp "$STAMP" "$VENV/.dolmetscher-stamp.tmp" && mv "$VENV/.dolmetscher-stamp.tmp" "$VENV/.dolmetscher-stamp" || fail
echo "done"
