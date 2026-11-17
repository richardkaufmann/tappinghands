#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Richard Kaufmann
# Regenerates Support/AppIcon.icns (blue fountain pen) from the app's own vector art.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
TMP=$(mktemp -d)
.build/release/TapHand --render-icon "$TMP"
iconutil -c icns "$TMP/AppIcon.iconset" -o Support/AppIcon.icns
cp "$TMP/AppIcon.iconset/icon_512x512@2x.png" docs/app-icon.png
rm -rf "$TMP"
echo "Wrote Support/AppIcon.icns"
