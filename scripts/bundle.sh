#!/bin/bash
# Builds Runwright.app (release) and Runwright-<version>.dmg into ./build.
#
# Usage: scripts/bundle.sh [--install] [--notarize]
#   --install    copy the app to /Applications
#   --notarize   submit the app and the DMG to Apple, wait, and staple the
#                tickets (needs SIGN_IDENTITY)
#
# Signing: ad-hoc by default. Set SIGN_IDENTITY to a "Developer ID Application: …"
# identity to sign with the hardened runtime and a secure timestamp. SIGN_KEYCHAIN
# optionally names the keychain file to find that identity in (CI uses a temporary one).
#
# Notarization credentials, either:
#   MACOS_NOTARY_KEY (path to AuthKey_XXXX.p8), MACOS_NOTARY_KEY_ID, MACOS_NOTARY_ISSUER
#   or MACOS_NOTARY_KEYCHAIN_PROFILE (from `xcrun notarytool store-credentials`)
set -euo pipefail

INSTALL=0
NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --notarize) NOTARIZE=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.."
# Version: $VERSION if set (CI passes it), else the v* tag on HEAD without its v.
if [[ -z "${VERSION:-}" ]]; then
  TAG="$(git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)"
  if [[ -n "$TAG" ]]; then
    VERSION="${TAG#v}"
  else
    VERSION="0.0.0"
    echo "warning: HEAD has no v* tag; building as $VERSION (tag a release, or set VERSION)" >&2
  fi
fi
APP="build/Runwright.app"

swift build -c release --product Runwright
BIN="$(swift build -c release --show-bin-path)/Runwright"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Runwright"

# Icon: every size macOS asks for, from the 1024 master.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Runwright</string>
  <key>CFBundleDisplayName</key><string>Runwright</string>
  <key>CFBundleIdentifier</key><string>com.krnblds.runwright</string>
  <key>CFBundleExecutable</key><string>Runwright</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  KEYCHAIN=()
  [[ -n "${SIGN_KEYCHAIN:-}" ]] && KEYCHAIN=(--keychain "$SIGN_KEYCHAIN")
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" ${KEYCHAIN[@]+"${KEYCHAIN[@]}"} "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP"

if [[ $NOTARIZE == 1 ]]; then
  [[ -n "${SIGN_IDENTITY:-}" ]] || { echo "--notarize needs SIGN_IDENTITY (Developer ID Application)" >&2; exit 2; }
  if [[ -n "${MACOS_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    CREDS=(--keychain-profile "$MACOS_NOTARY_KEYCHAIN_PROFILE")
  else
    : "${MACOS_NOTARY_KEY:?set MACOS_NOTARY_KEY or MACOS_NOTARY_KEYCHAIN_PROFILE}"
    CREDS=(--key "$MACOS_NOTARY_KEY" --key-id "${MACOS_NOTARY_KEY_ID:?}" --issuer "${MACOS_NOTARY_ISSUER:?}")
  fi
  ZIP="build/Runwright-${VERSION}.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" "${CREDS[@]}" --wait
  xcrun stapler staple "$APP"
  # Ship the stapled app.
  rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
  echo "Notarized $ZIP"
fi

# DMG: the (stapled, when notarized) app and an Applications link to drag it to.
DMG="build/Runwright-${VERSION}.dmg"
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Runwright ${VERSION}" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" ${KEYCHAIN[@]+"${KEYCHAIN[@]}"} "$DMG"
fi
if [[ $NOTARIZE == 1 ]]; then
  xcrun notarytool submit "$DMG" "${CREDS[@]}" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi
echo "Built $DMG"

if [[ $INSTALL == 1 ]]; then
  rm -rf /Applications/Runwright.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Runwright.app"
fi
