#!/usr/bin/env bash
# Builds the Electron app, installs it to ~/Applications/Pipeline Tracer.app, and starts it at login (LaunchAgent).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Pipeline Tracer.app"
APP_DEST="$HOME/Applications/$APP_NAME"
BIN="$APP_DEST/Contents/MacOS/Pipeline Tracer"
LABEL="com.kris.pipelinetracer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if ! command -v npm >/dev/null; then
  echo "npm is required (Node.js 20 or newer)" >&2
  exit 1
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if (( NODE_MAJOR < 20 )); then
  echo "Node.js 20 or newer is required (found $(node -v))" >&2
  exit 1
fi
if ! command -v glab >/dev/null && ! command -v gh >/dev/null; then
  echo "warning: neither glab nor gh is on PATH; install one and sign in, or the panel stays empty" >&2
fi

npm install
npm run pack:mac

APP_SRC="$(find "$ROOT/release" -maxdepth 3 -name "$APP_NAME" -type d 2>/dev/null | head -1 || true)"
if [[ -z "${APP_SRC}" ]]; then
  echo "$APP_NAME not found under release/" >&2
  exit 1
fi

# Stop the login agent, the Swift build (PipelineTracer), and any earlier Electron build.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
pkill -x PipelineTracer 2>/dev/null || true
pkill -f "$APP_NAME/Contents/MacOS/Pipeline Tracer" 2>/dev/null || true

mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
ditto "$APP_SRC" "$APP_DEST"
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DEST" >/dev/null 2>&1 || true

# Same label as the Swift installer, so this replaces its login item instead of adding a second one.
mkdir -p "$HOME/Library/LaunchAgents"
cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict>
</plist>
PLIST
launchctl bootstrap "$DOMAIN" "$PLIST"

mkdir -p "$HOME/bin"
cat >"$HOME/bin/pipeline-tracer" <<'EOF'
#!/usr/bin/env bash
APP="$HOME/Applications/Pipeline Tracer.app"
MATCH="Pipeline Tracer.app/Contents/MacOS/Pipeline Tracer"
case "${1:-}" in
  start) open -a "$APP" ;;
  stop) pkill -f "$MATCH" 2>/dev/null || true ;;
  status)
    if pgrep -f "$MATCH" >/dev/null; then
      echo "running"
    else
      echo "stopped"
    fi
    ;;
  *)
    echo "usage: pipeline-tracer {start|stop|status}"
    exit 1
    ;;
esac
EOF
chmod +x "$HOME/bin/pipeline-tracer"

echo "Installed $APP_DEST and enabled login start ($PLIST)"
echo "CLI: pipeline-tracer start|stop|status (ensure ~/bin is on PATH)"
