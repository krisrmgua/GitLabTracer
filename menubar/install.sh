#!/bin/bash
# Builds GitLab Tracer.app, installs it to ~/Applications, and starts it at login (LaunchAgent).
set -euo pipefail
cd "$(dirname "$0")"

LABEL="com.kris.gitlabtracer"
APP_DEST="$HOME/Applications/GitLab Tracer.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

./make-app.sh
pkill -x GitLabTracer 2>/dev/null || true
rm -rf "$APP_DEST"
cp -R "GitLab Tracer.app" "$APP_DEST"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APP_DEST/Contents/MacOS/GitLabTracer</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict>
</plist>
PLIST

DOMAIN="gui/$(id -u)"
# One-time cleanup of the old Toolbelt name (app bundle and login agent).
launchctl bootout "$DOMAIN/com.kris.toolbelt" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.kris.toolbelt.plist"
rm -rf "$HOME/Applications/Toolbelt.app"
# One-time cleanup of the old Deploymentor name. Saved options and the menu bar position carry over.
launchctl bootout "$DOMAIN/com.kris.deploymentor" 2>/dev/null || true
pkill -f "$HOME/Applications/Deploymentor.app/Contents/MacOS/Deploymentor" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.kris.deploymentor.plist"
rm -rf "$HOME/Applications/Deploymentor.app"
if defaults read com.kris.deploymentor >/dev/null 2>&1 && ! defaults read "$LABEL" >/dev/null 2>&1; then
  defaults export com.kris.deploymentor - | sed 's/<key>deploymentor\./<key>gitlabtracer./' | defaults import "$LABEL" -
fi
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed $APP_DEST and enabled login start ($PLIST)"
