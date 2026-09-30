#!/bin/zsh
# Builds a Release copy of Chordy and zips it into build/Chordy-<version>.zip for a GitHub Release.
# Signed with your free Personal Team certificate; not notarized (see README → Installing).
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="${TMPDIR:-/tmp}/chordy-release"
rm -rf "$DERIVED"
xcodebuild -project chordy.xcodeproj -scheme chordy -configuration Release -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build

APP="$DERIVED/Build/Products/Release/Chordy.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p build
ZIP="build/Chordy-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
codesign --verify --deep --strict "$APP" && echo "Signature OK"
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1)). Upload it to a GitHub Release."
