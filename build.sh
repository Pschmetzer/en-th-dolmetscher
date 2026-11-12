#!/bin/bash
# Baut Dolmetscher.app.  Nutzung:  ./build.sh [--install]
#   DOLMETSCHER_PYTHON=/pfad/zu/python  – vorhandenes Python mit faster-whisper verwenden
#   sonst wird eine venv unter ~/Library/Application Support/Dolmetscher/venv angelegt.
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
    if command -v uv >/dev/null; then uv pip install -q --python "$PY" faster-whisper edge-tts; else "$SUPPORT/venv/bin/pip" install -q --upgrade pip faster-whisper edge-tts; fi
  fi
fi
"$PY" -c "import faster_whisper" || { echo "faster-whisper fehlt in $PY"; exit 1; }
"$PY" -c "import edge_tts" 2>/dev/null || echo "Hinweis: edge-tts fehlt in $PY – es wird die macOS-Stimme genutzt (pip install edge-tts)"

echo "→ Lade Whisper-Modell 'small' (einmalig) …"
"$PY" -c "from faster_whisper import WhisperModel; WhisperModel('small', device='cpu', compute_type='int8')"

echo "→ Kompiliere …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/Dolmetscher" app/DolmetscherApp.swift
cp dolmetscher.py "$APP/Contents/Resources/"
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

codesign -s - --force --deep "$APP" >/dev/null 2>&1
echo "✓ $APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Dolmetscher.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "✓ installiert: ~/Applications/Dolmetscher.app"
fi
