#!/usr/bin/env bash
# Builds a universal, signed Aurolight.app and packs it into build/Aurolight-<version>.dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/macos/Bundle/Info.plist")"
DMG="$ROOT/build/Aurolight-$VERSION.dmg"
STAGING="$ROOT/build/dmg"

ARCHS="arm64 x86_64" "$ROOT/scripts/bundle-app.sh"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$ROOT/build/Aurolight.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Aurolight -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGING"
echo "✓ $DMG"
