#!/bin/bash
# Baut Dolmetscher.app.  Nutzung:  ./build.sh [--install]
#   DOLMETSCHER_PYTHON=/pfad/zu/python  – vorhandenes Python mit faster-whisper verwenden
#   sonst wird eine venv unter ~/Library/Application Support/Dolmetscher/venv angelegt
#   und mit den Versionen aus requirements.txt bestückt (uv, falls vorhanden, sonst pip).
#   DOLMETSCHER_SIGN_IDENTITY="Name"  – mit festem (z. B. selbstsignierten) Zertifikat signieren,
#   damit macOS nach einem Neubau nicht erneut nach dem Mikrofon fragt (siehe CONTRIBUTING.md).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Dolmetscher.app
SUPPORT="$HOME/Library/Application Support/Dolmetscher"

FFMPEG="$(command -v ffmpeg || true)"
[ -n "$FFMPEG" ] || { echo "ffmpeg fehlt:  brew install ffmpeg"; exit 1; }

PY="${DOLMETSCHER_PYTHON:-}"
if [ -z "$PY" ]; then
  PY="$SUPPORT/venv/bin/python"
  if [ ! -x "$PY" ]; then
    echo "→ Lege Python-Umgebung an …"
    mkdir -p "$SUPPORT"
    if command -v uv >/dev/null; then uv venv -q "$SUPPORT/venv"; else python3 -m venv "$SUPPORT/venv"; fi
  fi
  echo "→ Installiere Abhängigkeiten (requirements.txt) …"
  if command -v uv >/dev/null; then uv pip install -q --python "$PY" -r requirements.txt
  else "$PY" -m pip install -q --upgrade pip && "$PY" -m pip install -q -r requirements.txt; fi
fi
"$PY" -c "import faster_whisper" || { echo "faster-whisper fehlt in $PY"; exit 1; }
"$PY" -c "import edge_tts" 2>/dev/null || echo "Hinweis: edge-tts fehlt in $PY – es wird die macOS-Stimme genutzt (pip install edge-tts)"

echo "→ Lade Whisper-Modelle medium, small und Thai (~3,5 GB) (einmalig) …"
"$PY" -c "from faster_whisper import WhisperModel as W; W('medium', device='cpu', compute_type='int8'); W('small', device='cpu', compute_type='int8'); W('Vinxscribe/biodatlab-whisper-th-medium-faster', device='cpu', compute_type='int8')"

echo "→ Kompiliere …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/Dolmetscher" app/DolmetscherApp.swift
cp dolmetscher.py profiles.py "$APP/Contents/Resources/"
cp app/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Dolmetscher</string>
  <key>CFBundleDisplayName</key><string>Dolmetscher</string>
  <key>CFBundleIdentifier</key><string>io.github.dolmetscher.en-th</string>
  <key>CFBundleExecutable</key><string>Dolmetscher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Der Dolmetscher hört zu, um Englisch und Thai zu übersetzen.</string>
  <key>DolmetscherPython</key><string>$PY</string>
  <key>DolmetscherFFmpeg</key><string>$FFMPEG</string>
</dict></plist>
PLIST

SIGN="${DOLMETSCHER_SIGN_IDENTITY:--}"
if ! codesign -s "$SIGN" --force --deep "$APP" >/dev/null 2>&1; then
  echo "Signieren mit '$SIGN' fehlgeschlagen – nutze Ad-hoc-Signatur"
  codesign -s - --force --deep "$APP" >/dev/null 2>&1
fi
echo "✓ $APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Dolmetscher.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "✓ installiert: ~/Applications/Dolmetscher.app"
fi
