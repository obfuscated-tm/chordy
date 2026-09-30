#!/bin/zsh
# Builds a Release copy of Chordy and zips it into build/Chordy-<version>.zip for a GitHub Release.
# Signed with your free Personal Team certificate; not notarized (see README → Installing).
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="${TMPDIR:-/tmp/}chordy-release"
rm -rf "$DERIVED"
# "Chordy App", not "chordy": that name is shared with the CLI scheme from ChordyCore.
LOG="$DERIVED.log"
xcodebuild -project chordy.xcodeproj -scheme "Chordy App" -configuration Release -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates -skipMacroValidation build > "$LOG" 2>&1 \
  || { grep -E "error:" "$LOG" | head -20; echo "Build failed, full log: $LOG" >&2; exit 1; }

APP="$DERIVED/Build/Products/Release/Chordy.app"
[ -d "$APP" ] || { echo "Build produced no Chordy.app; see $LOG." >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p build
ZIP="build/Chordy-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
codesign --verify --deep --strict "$APP" && echo "Signature OK"
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1)). Upload it to a GitHub Release."
