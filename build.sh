#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Richard Kaufmann
# Builds build/TapHand.app (release, ad-hoc signed). Usage: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/TapHand.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TapHand "$APP/Contents/MacOS/TapHand"
cp Support/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate with tools/make_icon.sh
codesign --force --sign - "$APP"
echo "Built $APP"
