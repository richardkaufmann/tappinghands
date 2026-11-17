#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Richard Kaufmann
# Builds a Developer-ID-signed, notarized, stapled TapHand and zips it as dist/TapHand-<version>.zip.
# With --publish, also creates GitHub release v<version> with that zip attached.
#
# One-time setup (you type the app-specific password; it goes straight into your keychain, never into a file):
#   xcrun notarytool store-credentials tappinghands-notary --apple-id "<your Apple ID email>" --team-id 7455GAJKTL
# (App-specific password: appleid.apple.com > Sign-In and Security > App-Specific Passwords.)
#
# Usage: tools/release.sh [--publish]
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE=${NOTARY_PROFILE:-tappinghands-notary}
IDENTITY="Developer ID Application: Richard Kaufmann (7455GAJKTL)"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)
APP=build/TapHand.app
ZIP="dist/TapHand-$VERSION.zip"

./build.sh
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"   # hardened runtime: required to notarize
codesign --verify --strict --verbose=2 "$APP"
mkdir -p dist && rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"                     # re-zip with the ticket stapled
spctl --assess --type execute --verbose=2 "$APP"
shasum -a 256 "$ZIP"

if [[ "${1:-}" == "--publish" ]]; then
    gh release create "v$VERSION" "$ZIP" --title "TapHand $VERSION" \
        --notes "Signed with Developer ID and notarized by Apple. Unzip, drag TapHand.app to /Applications, open it."
fi
