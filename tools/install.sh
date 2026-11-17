#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Richard Kaufmann
# Builds TapHand, installs it to /Applications and makes it open at login (per-user LaunchAgent).
# Re-run after changes to update the installed copy. Uninstall: tools/install.sh --uninstall
set -euo pipefail
cd "$(dirname "$0")/.."
APP=/Applications/TapHand.app
PLIST="$HOME/Library/LaunchAgents/local.taphand.plist"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
    launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    pkill -x TapHand || true
    rm -rf "$APP"
    echo "Uninstalled TapHand (settings kept: defaults delete local.taphand to clear them)"
    exit 0
fi

./build.sh
pkill -x TapHand || true
sleep 0.5
rm -rf "$APP"
ditto build/TapHand.app "$APP"

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.taphand</string>
    <key>ProgramArguments</key>
    <array><string>/usr/bin/open</string><string>-a</string><string>$APP</string></array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null
launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"     # RunAtLoad: launches it now, and at every login
sleep 2
pgrep -x TapHand >/dev/null && echo "Installed $APP; running pid $(pgrep -x TapHand); opens at login via $PLIST"
