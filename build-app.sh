#!/bin/bash
# Builds a release binary and wraps it in build/MinimalCapture.app.
# No entitlements are applied, so the app is NOT sandboxed (required for global hotkeys).
#
# Options (environment variables):
#   SIGN_IDENTITY  Code-signing identity. Default: the first one in your keychain,
#                  or ad-hoc if there is none. Use "-" to force ad-hoc.
#   OUT_DIR        Where to put the .app. Default: build
#   UNIVERSAL=1    Build for Apple silicon and Intel (needs full Xcode).
set -euo pipefail
cd "$(dirname "$0")"

OUT_DIR="${OUT_DIR:-build}"
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$OUT_DIR/MinimalCapture.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MinimalCapture" "$APP/Contents/MacOS/MinimalCapture"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate with: swift Support/make-icon.swift

# Sign with a real identity when one exists so the Screen Recording grant survives rebuilds.
# Ad-hoc signatures change on every build, and macOS then asks for permission again.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"

if [ "${IDENTITY:--}" = "-" ]; then
    echo "Built $APP (ad-hoc signed)"
else
    echo "Built $APP (signed with a keychain identity)"
fi
