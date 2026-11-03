#!/usr/bin/env bash
# Builds Pipeline Tracer.app, installs it to ~/Applications, and starts it at login (LaunchAgent).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LABEL="com.kris.pipelinetracer"
APP_NAME="Pipeline Tracer.app"
APP_DEST="$HOME/Applications/$APP_NAME"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if ! command -v npm >/dev/null; then
  echo "npm is required. Install Node.js 20+ (brew install node)." >&2
  exit 1
fi

for tool in glab gh; do
  if ! command -v "$tool" >/dev/null; then
    echo "note: $tool not found on PATH. Install it with: brew install $tool" >&2
  fi
done

npm install
npm run pack:mac

APP_SRC="$(find "$ROOT/release" -maxdepth 3 -name "$APP_NAME" -type d 2>/dev/null | head -1 || true)"
if [[ -z "$APP_SRC" ]]; then
  echo "$APP_NAME not found under release/" >&2
  exit 1
fi

DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
# The Swift build's binary was PipelineTracer; the Electron build's is "Pipeline Tracer".
pkill -x PipelineTracer 2>/dev/null || true
pkill -f "$APP_NAME/Contents/MacOS/Pipeline Tracer" 2>/dev/null || true

mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"
# Locally built and unsigned: drop the quarantine flag so Gatekeeper does not block launch.
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APP_DEST/Contents/MacOS/Pipeline Tracer</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict>
</plist>
PLIST

launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed $APP_DEST and enabled login start ($PLIST)"
