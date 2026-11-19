#!/bin/bash
# Builds dist/MinimalCapture.zip, signed with a Developer ID and notarised by Apple, so it
# opens on other Macs without the "unidentified developer" warning.
#
# One-time setup (needs a paid Apple Developer Program membership):
#   1. Create a "Developer ID Application" certificate:
#      Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2. Store notarisation credentials in your keychain under the name "MinimalCapture":
#      xcrun notarytool store-credentials MinimalCapture --apple-id <your Apple ID> --team-id <your team ID>
#      (it asks for an app-specific password from https://account.apple.com)
#
# Options (environment variables):
#   NOTARY_PROFILE  Keychain profile name. Default: MinimalCapture
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-MinimalCapture}"
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [ -z "$IDENTITY" ]; then
    echo "No 'Developer ID Application' certificate found in your keychain. See the notes at the top of this script." >&2
    exit 1
fi

APP="dist/MinimalCapture.app"
ZIP="dist/MinimalCapture.zip"

# Universal build; build-app.sh's own signature is replaced below.
UNIVERSAL=1 SIGN_IDENTITY=- OUT_DIR=dist ./build-app.sh

# Notarisation requires the hardened runtime and a secure timestamp.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# Attach the notarisation ticket to the app, then zip again so the download carries it.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

spctl --assess --type execute --verbose "$APP"
echo "Ready: $ZIP"
