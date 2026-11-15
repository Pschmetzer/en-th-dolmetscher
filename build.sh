#!/bin/bash
# Baut Dolmetscher.app.  Nutzung:  ./build.sh [--install] [--release]
#   --install   danach nach ~/Applications kopieren
#   --release   Release-Bau: Developer-ID-Signatur mit Hardened Runtime, optional Notarisierung, ZIP + SHA256
#               in build/. Bricht ab, wenn DOLMETSCHER_SIGN_IDENTITY fehlt (kein Ad-hoc-Fallback).
#   DOLMETSCHER_PYTHON=/pfad/zu/python  – vorhandenes Python mit faster-whisper verwenden
#   sonst wird eine venv unter ~/Library/Application Support/Dolmetscher/venv angelegt
#   und mit requirements.txt bestückt (alle Pakete fest, mit Hashes; uv, falls vorhanden, sonst pip; Python >= 3.12).
#   DOLMETSCHER_SIGN_IDENTITY="Name"  – mit festem (z. B. selbstsignierten) Zertifikat signieren,
#   damit macOS nach einem Neubau nicht erneut nach dem Mikrofon fragt (siehe CONTRIBUTING.md).
#   DOLMETSCHER_SKIP_MODELS=1 – Modell-Download überspringen (nur CI/Strukturprüfung; die App lädt sie dann beim ersten Start)
#   DOLMETSCHER_MODELS="medium small th" – welche Modelle vorab laden (Standard; zusätzlich möglich: best = large-v3-turbo)
#   DOLMETSCHER_NOTARY_PROFILE="name" – nur mit --release: notarytool-Keychain-Profil
#   (xcrun notarytool store-credentials), dann wird notarisiert und geheftet.
# Version: aus pyproject.toml ([project] version); Build-Nummer: Anzahl der Git-Commits (sonst 1).
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0
RELEASE=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --release) RELEASE=1 ;;
    -h|--help) sed -n '2,/^set /p' "$0" | sed '$d'; exit 0 ;;
    *) echo "Unbekannte Option: $arg  (erlaubt: --install, --release)"; exit 2 ;;
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
fi

# Version und Build-Nummer aus einer Quelle.
VERSION="$(sed -n 's/^version *= *"\([^"]*\)".*/\1/p' pyproject.toml | head -n 1)"
[ -n "$VERSION" ] || { echo "Version in pyproject.toml nicht gefunden"; exit 1; }
BUILD_NO="$(git rev-list --count HEAD 2>/dev/null || true)"
case "$BUILD_NO" in ''|*[!0-9]*) BUILD_NO=1 ;; esac
YEAR="$(date +%Y)"

FFMPEG="$(command -v ffmpeg || true)"
[ -n "$FFMPEG" ] || { echo "ffmpeg fehlt:  brew install ffmpeg"; exit 1; }

PY="${DOLMETSCHER_PYTHON:-}"
if [ -z "$PY" ]; then
  PY="$SUPPORT/venv/bin/python"
  if [ ! -x "$PY" ]; then
    echo "→ Lege Python-Umgebung an …"
    mkdir -p "$SUPPORT"
    if command -v uv >/dev/null; then uv venv -q --python ">=3.12" "$SUPPORT/venv"
    else "$(command -v python3.12 || command -v python3)" -m venv "$SUPPORT/venv"; fi
  fi
  # requirements.txt ist für Python >= 3.12 aufgelöst (numpy 2.5 braucht 3.12).
  "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' || {
    echo "Python >= 3.12 nötig, die venv hat $("$PY" -V 2>&1)."
    echo "Abhilfe: brew install python@3.12 (oder uv), dann  rm -rf \"$SUPPORT/venv\"  und ./build.sh erneut."
    exit 1
  }
  echo "→ Installiere Abhängigkeiten (requirements.txt, mit Hash-Prüfung) …"
  if command -v uv >/dev/null; then uv pip install -q --python "$PY" --require-hashes -r requirements.txt
  else "$PY" -m pip install -q --require-hashes -r requirements.txt; fi
fi
"$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' \
  || { echo "Python >= 3.10 nötig, gefunden: $("$PY" -V 2>&1)"; exit 1; }
"$PY" -c "import faster_whisper" || { echo "faster-whisper fehlt in $PY"; exit 1; }
"$PY" -c "import edge_tts" 2>/dev/null || echo "Hinweis: edge-tts fehlt in $PY – es wird die macOS-Stimme genutzt (pip install edge-tts)"

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
swiftc -O -parse-as-library -o "$NEWAPP/Contents/MacOS/Dolmetscher" app/*.swift
cp dolmetscher.py profiles.py presets.py "$NEWAPP/Contents/Resources/"
cp -R presets "$NEWAPP/Contents/Resources/presets"
cp app/AppIcon.icns "$NEWAPP/Contents/Resources/"

# Lokalisierte Mikrofon-Begründung (die Info.plist enthält die deutsche Grundfassung).
write_strings() {   # Sprache, Text
  mkdir -p "$NEWAPP/Contents/Resources/$1.lproj"
  printf '"NSMicrophoneUsageDescription" = "%s";\n' "$2" > "$NEWAPP/Contents/Resources/$1.lproj/InfoPlist.strings"
}
write_strings de "Der Dolmetscher hört zu, um Englisch und Thai zu übersetzen."
write_strings en "The interpreter listens to translate English and Thai."
write_strings th "ตัวแปลภาษาฟังเสียงของคุณเพื่อแปลระหว่างภาษาอังกฤษและภาษาไทย"

# Pfade unter $HOME als "~/…" einbetten (die App expandiert die Tilde), damit die
# Info.plist keinen Benutzernamen enthält. ffmpeg: die App sucht zusätzlich in
# /opt/homebrew/bin und /usr/local/bin.
# shellcheck disable=SC2088  # die Tilde soll wörtlich in die Info.plist
tilde() { case "$1" in "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }
xml() { local s="${1//&/&amp;}"; s="${s//</&lt;}"; printf '%s' "${s//>/&gt;}"; }
PY_PLIST="$(xml "$(tilde "$PY")")"
FFMPEG_PLIST="$(xml "$(tilde "$FFMPEG")")"

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
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © $YEAR Dolmetscher contributors. MIT License.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Der Dolmetscher hört zu, um Englisch und Thai zu übersetzen.</string>
  <key>DolmetscherPython</key><string>$PY_PLIST</string>
  <key>DolmetscherFFmpeg</key><string>$FFMPEG_PLIST</string>
</dict></plist>
PLIST
plutil -lint "$NEWAPP/Contents/Info.plist" >/dev/null

# Ohne --deep: das Bundle enthält keine verschachtelten Bundles oder Frameworks.
SIGN="${DOLMETSCHER_SIGN_IDENTITY:--}"
if [ "$RELEASE" = 1 ]; then
  codesign -s "$SIGN" --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$NEWAPP"
elif ! codesign -s "$SIGN" --force "$NEWAPP"; then
  echo "Signieren mit '$SIGN' fehlgeschlagen (Meldung oben) – nutze Ad-hoc-Signatur"
  codesign -s - --force "$NEWAPP"
fi
codesign --verify --strict --verbose=2 "$NEWAPP"

# Erst jetzt das alte Bundle ersetzen.
rm -rf "$APP"
mv "$NEWAPP" "$APP"
echo "✓ $APP  (Version $VERSION, Build $BUILD_NO)"

if [ "$RELEASE" = 1 ]; then
  ZIP="build/Dolmetscher-$VERSION.zip"
  rm -f "$ZIP" "$ZIP.sha256"
  if [ -n "${DOLMETSCHER_NOTARY_PROFILE:-}" ]; then
    echo "→ Notarisiere (kann einige Minuten dauern) …"
    ditto -c -k --keepParent "$APP" "$STAGE/notarize.zip"
    xcrun notarytool submit "$STAGE/notarize.zip" --keychain-profile "$DOLMETSCHER_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
  else
    echo "Hinweis: DOLMETSCHER_NOTARY_PROFILE nicht gesetzt – das Bundle ist signiert, aber nicht notarisiert."
  fi
  ditto -c -k --keepParent "$APP" "$ZIP"
  (cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
  echo "✓ $ZIP"
  echo "✓ $ZIP.sha256"
fi

if [ "$INSTALL" = 1 ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Dolmetscher.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "✓ installiert: ~/Applications/Dolmetscher.app"
fi
