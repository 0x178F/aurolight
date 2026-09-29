#!/usr/bin/env bash
# Screen Recording permission is tied to the signature: set SIGN_IDENTITY or scripts/.signing-identity.
# ARCHS="arm64 x86_64" builds a universal binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY_FILE="$ROOT/scripts/.signing-identity"
if [[ -z "${SIGN_IDENTITY:-}" && -f "$IDENTITY_FILE" ]]; then
  SIGN_IDENTITY="$(head -n 1 "$IDENTITY_FILE")"
fi
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="-"
elif [[ "$SIGN_IDENTITY" != "-" ]] && ! security find-identity -p codesigning | grep -Fq -- "$SIGN_IDENTITY"; then
  echo "error: no code-signing identity matching '$SIGN_IDENTITY' in the keychain." >&2
  echo "Fix scripts/.signing-identity or SIGN_IDENTITY, or unset both to sign ad-hoc." >&2
  exit 1
fi
APP="$ROOT/build/Aurolight.app"

BUILD_ARGS=(--package-path "$ROOT/macos" -c release)
for arch in ${ARCHS:-}; do BUILD_ARGS+=(--arch "$arch"); done
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Aurolight" "$APP/Contents/MacOS/Aurolight"
cp "$ROOT/macos/Bundle/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/macos/Bundle/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/macos/Bundle/Intro.mp4" "$APP/Contents/Resources/Intro.mp4"

codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
echo "✓ $APP (signed: $SIGN_IDENTITY)"
