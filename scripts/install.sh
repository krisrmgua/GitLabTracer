#!/usr/bin/env bash
# Builds the Electron app, installs it to ~/Applications/Pipeline Tracer.app.
# Login start is Preferences → Open at login (Electron login item), not a LaunchAgent.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Pipeline Tracer.app"
APP_DEST="$HOME/Applications/$APP_NAME"
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

# Stop the Swift build (PipelineTracer) and any earlier Electron build.
pkill -x PipelineTracer 2>/dev/null || true
pkill -f "$APP_NAME/Contents/MacOS/Pipeline Tracer" 2>/dev/null || true

# Swift / older Electron installs used a LaunchAgent. Electron registers a login item instead.
if [[ -f "$PLIST" ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Removed the LaunchAgent ($PLIST)"
fi

mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
ditto "$APP_SRC" "$APP_DEST"
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DEST" >/dev/null 2>&1 || true

# First packaged launch applies Open at login from prefs (default on).
open -a "$APP_DEST"

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

echo "Installed $APP_DEST"
echo "Open at login: Preferences in the panel (default on)"
echo "CLI: pipeline-tracer start|stop|status (ensure ~/bin is on PATH)"
