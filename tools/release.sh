#!/bin/bash
# Builds a universal Shotshelf.app and packages it as dist/Shotshelf-VERSION.dmg.
#   tools/release.sh 1.2.0
#
# Signing and notarization are optional and happen when these are set:
#   SHOTSHELF_SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE            a profile saved with `xcrun notarytool store-credentials`, or
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   (an app-specific password)
# Without them the DMG holds an ad hoc signed app, which macOS asks people to approve once.
set -euo pipefail
cd "$(dirname "$0")/.."

# Never ship a personal local signing certificate: ad hoc unless a Developer ID is given.
export SHOTSHELF_SIGN_IDENTITY="${SHOTSHELF_SIGN_IDENTITY:--}"
VERSION="${1:?usage: tools/release.sh VERSION}"
VERSION="${VERSION#v}"
DMG="dist/Shotshelf-$VERSION.dmg"
STAGE=build/dmg

./build.sh --universal --version "$VERSION"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" dist
cp -R build/Shotshelf.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "Creating $DMG..."
hdiutil create -volname "Shotshelf $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

if [[ "${SHOTSHELF_SIGN_IDENTITY:-}" == "Developer ID Application"* ]]; then
  codesign --force --sign "$SHOTSHELF_SIGN_IDENTITY" --timestamp "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    AUTH=(--keychain-profile "$NOTARY_PROFILE")
  elif [ -n "${APPLE_ID:-}" ]; then
    AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  fi
  if [ -n "${AUTH+x}" ]; then
    echo "Notarizing (this usually takes a few minutes)..."
    xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait
    xcrun stapler staple "$DMG"
  else
    echo "Signed with a Developer ID but not notarized: set NOTARY_PROFILE or APPLE_ID to notarize."
  fi
else
  echo "Not signed with a Developer ID: macOS will ask people to approve the app once (see README)."
fi

(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Built $DMG"
