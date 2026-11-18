#!/bin/bash
# Baut Dolmetscher.app.  Nutzung:  ./build.sh [--install] [--release]
#   --install   danach nach ~/Applications kopieren
#   --no-notarize  nur mit --release: ohne Notarisierung bauen (ZIP/DMG heißen dann ...-unnotarized)
#   --bundle-wheels  Wheels aus requirements.txt mitliefern (Contents/Resources/offline/wheels): Einrichtung ohne PyPI
#   --release   Release-Bau: Developer-ID-Signatur mit Hardened Runtime, optional Notarisierung, ZIP + SHA256
#               in build/. Bricht ab, wenn DOLMETSCHER_SIGN_IDENTITY fehlt (kein Ad-hoc-Fallback).
# Die App ist eigenständig (nur Apple Silicon): Sie bringt uv (Contents/Helpers/uv), den Lock
# (requirements.txt) und setup-env.sh mit und richtet die Python-Umgebung beim ersten Start selbst ein
# (uv-verwaltetes Python 3.12 + Pakete nach ~/Library/Application Support/Dolmetscher/venv). Audio läuft
# über PyAV – kein Homebrew, kein ffmpeg. Die Info.plist enthält keine Pfade dieser Maschine.
# Zum Bauen nötig: Xcode-Command-Line-Tools und uv (Version UV_VERSION unten; brew install uv).
#   DOLMETSCHER_PYTHON=/pfad/zu/python  – Bau-Prüfung und Modell-Download mit diesem Python (wird nie verändert).
#   Zur Laufzeit nutzt die App ein Entwickler-Python nur über DOLMETSCHER_PYTHON in ihrer Umgebung oder
#   `defaults write io.github.dolmetscher.en-th DolmetscherPython /pfad/zu/python`.
#   Ohne DOLMETSCHER_PYTHON (nur ohne --release): die venv unter Application Support wird angelegt bzw. mit
#   requirements.txt abgeglichen (Hashes) und bekommt den Stempel – die App startet dann ohne Einrichtung.
#   DOLMETSCHER_SIGN_IDENTITY="Name"  – mit festem (z. B. selbstsignierten) Zertifikat signieren,
#   damit macOS nach einem Neubau nicht erneut nach dem Mikrofon fragt (siehe CONTRIBUTING.md).
#   DOLMETSCHER_SKIP_MODELS=1 – Modell-Download überspringen (nur CI/Strukturprüfung; die App lädt sie dann beim ersten Start)
#   DOLMETSCHER_SKIP_TRANSLATE_HELPER=1 – translate-helper (Offline-Übersetzung, macOS 26.4+) nicht bauen
#   DOLMETSCHER_MODELS="medium small th" – welche Modelle vorab laden (Standard; zusätzlich möglich: best = large-v3-turbo)
#   DOLMETSCHER_NOTARY_PROFILE="name" – nur mit --release: notarytool-Keychain-Profil
#   (xcrun notarytool store-credentials), dann wird notarisiert und geheftet.
# Version: aus pyproject.toml ([project] version); Build-Nummer: Anzahl der Git-Commits (sonst 1).
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0
RELEASE=0
NO_NOTARIZE=0
BUNDLE_WHEELS=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --release) RELEASE=1 ;;
    --no-notarize) NO_NOTARIZE=1 ;;
    --bundle-wheels) BUNDLE_WHEELS=1 ;;
    -h|--help) sed -n '2,/^set /p' "$0" | sed '$d'; exit 0 ;;
    *) echo "Unbekannte Option: $arg  (erlaubt: --install, --release, --no-notarize, --bundle-wheels)"; exit 2 ;;
  esac
done

APP=build/Dolmetscher.app
SUPPORT="$HOME/Library/Application Support/Dolmetscher"
ENTITLEMENTS=build-support/Dolmetscher.entitlements

# Release-Voraussetzungen früh prüfen, bevor etwas lange läuft.
if [ "$RELEASE" = 1 ]; then
  [ -n "${DOLMETSCHER_SIGN_IDENTITY:-}" ] || {
    echo "--release braucht DOLMETSCHER_SIGN_IDENTITY (z. B. \"Developer ID Application: Name (TEAMID)\")."
    echo "Ohne Zertifikat wird nicht signiert; für lokale Bauten ./build.sh ohne --release nutzen."
    exit 1
  }
  [ -f "$ENTITLEMENTS" ] || { echo "$ENTITLEMENTS fehlt"; exit 1; }
  # Nr. 43: ohne Notarisierung blockiert Gatekeeper das ZIP auf fremden Macs – nur mit ausdrücklichem --no-notarize.
  if [ -z "${DOLMETSCHER_NOTARY_PROFILE:-}" ] && [ "$NO_NOTARIZE" != 1 ]; then
    echo "--release braucht DOLMETSCHER_NOTARY_PROFILE (xcrun notarytool store-credentials) oder ausdrücklich --no-notarize."
    exit 1
  fi
fi

# Version und Build-Nummer aus einer Quelle.
VERSION="$(sed -n 's/^version *= *"\([^"]*\)".*/\1/p' pyproject.toml | head -n 1)"
[ -n "$VERSION" ] || { echo "Version in pyproject.toml nicht gefunden"; exit 1; }
BUILD_NO="$(git rev-list --count HEAD 2>/dev/null || true)"
case "$BUILD_NO" in ''|*[!0-9]*) BUILD_NO=1 ;; esac
YEAR="$(date +%Y)"

# uv wird mitgeliefert (fest gepinnte Version; Mindest-macOS des Binarys <= LSMinimumSystemVersion).
UV_VERSION="0.12.7"
MIN_MACOS="14.0"
[ "$(uname -m)" = arm64 ] || { echo "Gebaut wird nur auf Apple Silicon (die App ist arm64-only)."; exit 1; }
UV_BIN="$(command -v uv || true)"
[ -n "$UV_BIN" ] && UV_BIN="$(realpath "$UV_BIN")"     # Homebrew-Symlink auflösen: das Binary selbst kopieren
if [ -z "$UV_BIN" ]; then
  [ "$RELEASE" = 1 ] && { echo "uv fehlt (brew install uv) – ohne uv kann die App ihre Umgebung nicht einrichten."; exit 1; }
  echo "Hinweis: uv fehlt – die App kann ihre Umgebung auf anderen Macs nicht selbst einrichten (brew install uv)."
else
  UV_HAVE="$("$UV_BIN" --version | awk '{print $2}')"
  if [ "$UV_HAVE" != "$UV_VERSION" ]; then
    [ "$RELEASE" = 1 ] && { echo "uv $UV_HAVE gefunden, Release braucht uv $UV_VERSION (UV_VERSION in build.sh)."; exit 1; }
    echo "Hinweis: uv $UV_HAVE statt $UV_VERSION – für Releases die gepinnte Version nutzen."
  fi
  # Nr. 46: nur System-Bibliotheken – ein Homebrew-uv mit /opt/homebrew-Pfaden startet auf fremden Macs nicht.
  UV_LIBS="$(otool -L "$UV_BIN" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/)' || true)"
  if [ -n "$UV_LIBS" ]; then
    echo "uv ist gegen fremde Bibliotheken gelinkt (nicht /usr/lib, /System):"; echo "$UV_LIBS"
    echo "→ ein eigenständiges uv-Binary nutzen (z. B. das offizielle Release)."; exit 1
  fi
  UV_MINOS="$(vtool -show-build "$UV_BIN" 2>/dev/null | awk '/minos/ {print $2; exit}')"
  if [ -n "$UV_MINOS" ] && [ "$(printf '%s\n%s\n' "$UV_MINOS" "$MIN_MACOS" | sort -V | tail -n 1)" != "$MIN_MACOS" ]; then
    echo "uv braucht macOS $UV_MINOS, die App verspricht $MIN_MACOS – anderes uv-Binary nutzen."; exit 1
  fi
fi

PY="${DOLMETSCHER_PYTHON:-}"
OWN_VENV=0
if [ -z "$PY" ]; then
  OWN_VENV=1
  PY="$SUPPORT/venv/bin/python"
  if [ ! -x "$PY" ]; then
    echo "→ Lege Python-Umgebung an …"
    mkdir -p "$SUPPORT"
    if [ -n "$UV_BIN" ]; then "$UV_BIN" venv -q --python 3.12 "$SUPPORT/venv"
    else "$(command -v python3.12 || command -v python3)" -m venv "$SUPPORT/venv"; fi
  fi
  # requirements.txt ist für Python >= 3.12 aufgelöst (numpy 2.5 braucht 3.12).
  "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' || {
    echo "Python >= 3.12 nötig, die venv hat $("$PY" -V 2>&1)."
    echo "Abhilfe: brew install python@3.12 (oder uv), dann  rm -rf \"$SUPPORT/venv\"  und ./build.sh erneut."
    exit 1
  }
  # Bei jedem Bau abgleichen (installiert nur Abweichendes), damit der Stempel unten stimmt.
  echo "→ Gleiche Abhängigkeiten ab (requirements.txt, mit Hash-Prüfung) …"
  if [ -n "$UV_BIN" ]; then "$UV_BIN" pip install -q --python "$PY" --require-hashes -r requirements.txt
  else "$PY" -m pip install -q --require-hashes -r requirements.txt; fi
fi
"$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' \
  || { echo "Python >= 3.10 nötig, gefunden: $("$PY" -V 2>&1)"; exit 1; }
"$PY" -c "import faster_whisper" || { echo "faster-whisper fehlt in $PY"; exit 1; }
"$PY" -c "import av" || { echo "PyAV (av) fehlt in $PY – Audio läuft über PyAV"; exit 1; }
"$PY" -c "import edge_tts" 2>/dev/null || echo "Hinweis: edge-tts fehlt in $PY – es wird die macOS-Stimme genutzt (pip install edge-tts)"

# Eigene venv (nicht DOLMETSCHER_PYTHON): Stempel schreiben, damit die App sie ohne Einrichtung nutzt.
# Nur bei Python 3.12 – sonst richtet die App beim Start eine eigene (uv-verwaltete) Umgebung ein.
if [ "$OWN_VENV" = 1 ]; then
  if "$PY" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 12) else 1)'; then
    build-support/make-stamp.sh requirements.txt > "$SUPPORT/venv/.dolmetscher-stamp"
  else
    rm -f "$SUPPORT/venv/.dolmetscher-stamp"
    echo "Hinweis: $PY ist nicht Python 3.12 – die App richtet beim ersten Start ihre Umgebung neu ein."
  fi
else
  echo "Hinweis: DOLMETSCHER_PYTHON wird nur für den Bau genutzt; für die App:"
  echo "  defaults write io.github.dolmetscher.en-th DolmetscherPython \"$PY\""
fi

if [ "${DOLMETSCHER_SKIP_MODELS:-0}" = 1 ]; then
  echo "→ Modell-Download übersprungen (DOLMETSCHER_SKIP_MODELS=1, z. B. in CI)"
else
  MODELS="${DOLMETSCHER_MODELS:-medium small th}"
  echo "→ Lade Whisper-Modelle ($MODELS; medium+small+th ~3,5 GB, best +1,6 GB) (einmalig) …"
  # Namen und feste Revisionen kommen aus dolmetscher.py (MODEL_REVISIONS), wie in der Engine.
  # download_model lädt nur die Dateien (kein Modell im Speicher); fertige Dateien im Cache werden übersprungen.
  "$PY" - "$MODELS" <<'PYEOF'
import sys
from faster_whisper.utils import download_model
from dolmetscher import MODEL_REVISIONS, THAI_MODEL
alias = {"th": THAI_MODEL, "best": "large-v3-turbo"}
for arg in sys.argv[1].replace(",", " ").split():
    name = alias.get(arg, arg)
    if name not in MODEL_REVISIONS:
        sys.exit(f"Unbekanntes Modell '{arg}' (erlaubt: small, medium, best, th)")
    print(f"  {name} @ {MODEL_REVISIONS[name][:10]}", flush=True)
    download_model(name, revision=MODEL_REVISIONS[name])
PYEOF
fi

# Gebaut wird in einem temporären Verzeichnis; ein vorhandenes build/Dolmetscher.app
# wird erst ersetzt, wenn Compile, Signatur und Prüfung erfolgreich waren.
mkdir -p build
STAGE="$(mktemp -d build/.stage.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
NEWAPP="$STAGE/Dolmetscher.app"

echo "→ Kompiliere (Version $VERSION, Build $BUILD_NO) …"
mkdir -p "$NEWAPP/Contents/MacOS" "$NEWAPP/Contents/Resources"
# Release: -D RELEASE_BUILD schaltet Entwickler-Overrides (Python-Pfad per Einstellung) und die Klartext-Schlüsselkopie ab.
SWIFT_FLAGS=(-O -g -parse-as-library -target "arm64-apple-macos$MIN_MACOS")
[ "$RELEASE" = 1 ] && SWIFT_FLAGS+=(-D RELEASE_BUILD)
swiftc "${SWIFT_FLAGS[@]}" -o "$NEWAPP/Contents/MacOS/Dolmetscher" app/*.swift
cp dolmetscher.py avhelper.py profiles.py presets.py history_store.py hwprofile.py correction_learning.py \
   "$NEWAPP/Contents/Resources/"
# Gemeinsame Sprachtabelle: Engine (neben dolmetscher.py) und App (Bundle.main) lesen dieselbe Datei.
cp languages.json "$NEWAPP/Contents/Resources/languages.json"
# Einrichtung: Lock, Stempel (Lock-Hash + Python + Architektur), Skript, uv.
cp requirements.txt "$NEWAPP/Contents/Resources/requirements.txt"
cp build-support/setup-env.sh "$NEWAPP/Contents/Resources/setup-env.sh"
build-support/make-stamp.sh requirements.txt > "$NEWAPP/Contents/Resources/env-stamp"
if [ -n "$UV_BIN" ]; then
  mkdir -p "$NEWAPP/Contents/Helpers"
  cp "$UV_BIN" "$NEWAPP/Contents/Helpers/uv"
  chmod 755 "$NEWAPP/Contents/Helpers/uv"
fi
# Offline-Übersetzung (Apple Translation): translate-helper nach Contents/Helpers. Er nutzt APIs ab macOS 26.4 und
# wird deshalb mit eigenem Ziel (26.0) gebaut; die App selbst bleibt bei MIN_MACOS. Fehlt das SDK (älteres Xcode),
# wird er übersprungen – die App läuft dann ohne Offline-Übersetzung (die Einstellung ist ausgegraut).
HELPER_MIN_MACOS="26.0"
TH_IN="$NEWAPP/Contents/Helpers/translate-helper"
if [ "${DOLMETSCHER_SKIP_TRANSLATE_HELPER:-0}" = 1 ]; then
  echo "→ translate-helper übersprungen (DOLMETSCHER_SKIP_TRANSLATE_HELPER=1)"
else
  echo "→ Kompiliere translate-helper (macOS $HELPER_MIN_MACOS+) …"
  mkdir -p "$NEWAPP/Contents/Helpers"
  if ! swiftc -O -parse-as-library -target "arm64-apple-macos$HELPER_MIN_MACOS" -o "$TH_IN" \
       tools/translate-helper/main.swift; then
    rm -f "$TH_IN"
    echo "Hinweis: translate-helper ließ sich nicht bauen (SDK für macOS $HELPER_MIN_MACOS nötig) – ohne Offline-Übersetzung."
  fi
fi
if [ "$BUNDLE_WHEELS" = 1 ]; then
  # Nr. 50: Wheels des Locks mitliefern; setup-env.sh nutzt sie offline (uv pip sync --offline --find-links).
  echo "→ Lade Wheels für die Offline-Einrichtung (große Datei, ca. 400 MB) …"
  mkdir -p "$NEWAPP/Contents/Resources/offline/wheels"
  "$PY" -m pip download -q --require-hashes --only-binary=:all: --no-deps -r requirements.txt \
    -d "$NEWAPP/Contents/Resources/offline/wheels"
fi
cp -R presets "$NEWAPP/Contents/Resources/presets"
cp app/AppIcon.icns app/whatsnew.json "$NEWAPP/Contents/Resources/"

# Lokalisierte Mikrofon-Begründung (die Info.plist enthält die deutsche Grundfassung).
write_strings() {   # Sprache, Text
  mkdir -p "$NEWAPP/Contents/Resources/$1.lproj"
  printf '"NSMicrophoneUsageDescription" = "%s";\n' "$2" > "$NEWAPP/Contents/Resources/$1.lproj/InfoPlist.strings"
}
write_strings de "Der Dolmetscher hört zu, um zwischen den gewählten Sprachen zu übersetzen."
write_strings en "The interpreter listens to translate between the selected languages."
write_strings th "ตัวแปลภาษาฟังเสียงของคุณเพื่อแปลระหว่างภาษาที่เลือก"

# Keine Pfade dieser Maschine in der Info.plist: die App findet Python selbst (Paths.swift).

cat > "$NEWAPP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Dolmetscher</string>
  <key>CFBundleDisplayName</key><string>Dolmetscher</string>
  <key>CFBundleIdentifier</key><string>io.github.dolmetscher.en-th</string>
  <key>CFBundleExecutable</key><string>Dolmetscher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NO</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>CFBundleLocalizations</key><array><string>de</string><string>en</string><string>th</string></array>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>LSRequiresNativeExecution</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © $YEAR Dolmetscher contributors. MIT License.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Der Dolmetscher hört zu, um zwischen den gewählten Sprachen zu übersetzen.</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>io.github.dolmetscher.en-th</string>
    <key>CFBundleURLSchemes</key><array><string>dolmetscher</string></array>
  </dict></array>
</dict></plist>
PLIST
plutil -lint "$NEWAPP/Contents/Info.plist" >/dev/null

# Von innen nach außen signieren (kein --deep beim Signieren): zuerst die Helfer in Contents/Helpers (uv,
# translate-helper), dann das Bundle. Prüfen mit --deep: jede verschachtelte Signatur muss gültig sein.
# translate-helper läuft immer mit Hardened Runtime (braucht keine Ausnahmen: kein Netz, kein Mikrofon).
SIGN="${DOLMETSCHER_SIGN_IDENTITY:--}"
UV_IN="$NEWAPP/Contents/Helpers/uv"
sign_helpers() {   # Identität, weitere codesign-Optionen (Release: --timestamp)
  local id="$1"; shift
  if [ -f "$UV_IN" ]; then
    if [ "$RELEASE" = 1 ]; then
      codesign -s "$id" --force --options runtime "$@" --identifier io.github.dolmetscher.en-th.uv "$UV_IN" || return 1
    else
      codesign -s "$id" --force "$@" --identifier io.github.dolmetscher.en-th.uv "$UV_IN" || return 1
    fi
  fi
  if [ -f "$TH_IN" ]; then
    codesign -s "$id" --force --options runtime "$@" \
      --identifier io.github.dolmetscher.en-th.translate-helper "$TH_IN" || return 1
  fi
}
if [ "$RELEASE" = 1 ]; then
  sign_helpers "$SIGN" --timestamp
  codesign -s "$SIGN" --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$NEWAPP"
else
  sign_helpers "$SIGN" || sign_helpers -
  if ! codesign -s "$SIGN" --force "$NEWAPP"; then
    echo "Signieren mit '$SIGN' fehlgeschlagen (Meldung oben) – nutze Ad-hoc-Signatur"
    sign_helpers -
    codesign -s - --force "$NEWAPP"
  fi
fi
if [ -f "$TH_IN" ]; then
  TH_SIG="$(codesign -d --verbose=2 "$TH_IN" 2>&1 || true)"   # erst lesen: grep -q in der Pipe + pipefail = SIGPIPE
  case "$TH_SIG" in
    *flags=*runtime*) ;;
    *) echo "translate-helper ist nicht mit Hardened Runtime signiert"; exit 1 ;;
  esac
fi
codesign --verify --deep --strict --verbose=2 "$NEWAPP"
# Nr. 46: das signierte, mitgelieferte uv muss starten (fremde Bibliotheken, Signaturfehler).
if [ -f "$UV_IN" ]; then "$UV_IN" --version >/dev/null || { echo "Mitgeliefertes uv startet nicht."; exit 1; }; fi

# Erst jetzt das alte Bundle ersetzen.
rm -rf "$APP"
mv "$NEWAPP" "$APP"
echo "✓ $APP  (Version $VERSION, Build $BUILD_NO)"

if [ "$RELEASE" = 1 ]; then
  SUFFIX=""
  [ -n "${DOLMETSCHER_NOTARY_PROFILE:-}" ] || SUFFIX="-unnotarized"
  ZIP="build/Dolmetscher-$VERSION$SUFFIX.zip"
  DMG="build/Dolmetscher-$VERSION$SUFFIX.dmg"
  rm -f "$ZIP" "$ZIP.sha256" "$DMG" "$DMG.sha256"
  if [ -n "${DOLMETSCHER_NOTARY_PROFILE:-}" ]; then
    echo "→ Notarisiere (kann einige Minuten dauern) …"
    ditto -c -k --keepParent "$APP" "$STAGE/notarize.zip"
    notarize() {   # Datei: einreichen, bei Ablehnung das Protokoll (Gründe) ausgeben und abbrechen
      local out id status
      out="$(xcrun notarytool submit "$1" --keychain-profile "$DOLMETSCHER_NOTARY_PROFILE" --wait --output-format json)" || true
      echo "$out"
      id="$(printf '%s' "$out" | plutil -extract id raw -o - - 2>/dev/null || true)"
      status="$(printf '%s' "$out" | plutil -extract status raw -o - - 2>/dev/null || true)"
      if [ "$status" != "Accepted" ]; then
        echo "Notarisierung nicht angenommen (Status: ${status:-unbekannt})."
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$DOLMETSCHER_NOTARY_PROFILE" || true
        exit 1
      fi
    }
    notarize "$STAGE/notarize.zip"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl -a -vv -t exec "$APP"
  else
    echo "Hinweis: ausdrücklich ohne Notarisierung (--no-notarize) – Gatekeeper warnt auf fremden Macs."
  fi
  ditto -c -k --keepParent "$APP" "$ZIP"
  (cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
  echo "✓ $ZIP"
  echo "✓ $ZIP.sha256"
  # Nr. 49: DMG mit Programme-Verknüpfung (Standardweg; die App läuft dann nicht aus Downloads).
  DMGDIR="$(mktemp -d "$STAGE/dmg.XXXXXX")"
  cp -R "$APP" "$DMGDIR/"
  ln -s /Applications "$DMGDIR/Applications"
  hdiutil create -quiet -volname Dolmetscher -srcfolder "$DMGDIR" -format UDZO -ov "$DMG"
  codesign -s "${DOLMETSCHER_SIGN_IDENTITY}" --timestamp "$DMG"
  if [ -n "${DOLMETSCHER_NOTARY_PROFILE:-}" ]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
  fi
  (cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
  echo "✓ $DMG"
  # Nr. 45: Debug-Symbole neben dem ZIP, zum Auflösen von Absturzberichten dieser Build-Nummer.
  rm -rf "build/Dolmetscher-$VERSION.dSYM"
  dsymutil "$APP/Contents/MacOS/Dolmetscher" -o "build/Dolmetscher-$VERSION.dSYM" 2>/dev/null \
    && echo "✓ build/Dolmetscher-$VERSION.dSYM" || echo "Hinweis: dSYM nicht erzeugt."
fi

if [ "$INSTALL" = 1 ]; then
  # Nr. 393: Läuft die installierte App noch, liefe ihre Engine aus dem gelöschten Bundle weiter: erst beenden.
  RUNNING="$HOME/Applications/Dolmetscher.app/Contents/MacOS/Dolmetscher"
  if pgrep -f "$RUNNING" >/dev/null 2>&1; then
    echo "→ Beende die laufende Dolmetscher.app …"
    osascript -e 'quit app id "io.github.dolmetscher.en-th"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -f "$RUNNING" >/dev/null 2>&1 || break
      sleep 0.5
    done
    if pgrep -f "$RUNNING" >/dev/null 2>&1; then
      echo "Dolmetscher.app läuft noch – bitte beenden und ./build.sh --install erneut starten."; exit 1
    fi
  fi
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Dolmetscher.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "✓ installiert: ~/Applications/Dolmetscher.app"
fi
