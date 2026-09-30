#!/bin/zsh
# Builds Chordy, installs it to ~/Applications and launches it.
# Builds outside ~/Documents because iCloud/Finder extended attributes there break codesigning.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="${TMPDIR:-/tmp}/chordy-derived"
CONFIG="${1:-Debug}"

xcodebuild -project chordy.xcodeproj -scheme "Chordy App" -configuration "$CONFIG" -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates -skipMacroValidation -quiet build

pkill -x Chordy 2>/dev/null && sleep 1 || true
mkdir -p ~/Applications
rm -rf ~/Applications/Chordy.app
ditto "$DERIVED/Build/Products/$CONFIG/Chordy.app" ~/Applications/Chordy.app
open ~/Applications/Chordy.app
echo "Chordy is running — look for the waveform in the menu bar."
