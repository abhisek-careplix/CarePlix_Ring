#!/usr/bin/env bash
# Archive and export CarePlix Ring for distribution.
#   scripts/archive.sh                 # archive + export per ExportOptions.plist (TestFlight upload by default)
#   scripts/archive.sh --no-upload     # archive + export an .ipa locally (uses ExportOptions with destination=export)
# Requires: Xcode 15+, Config/Signing.xcconfig with your team, an App Store Connect app record for the bundle id.
set -euo pipefail
cd "$(dirname "$0")/.."
SCHEME="CarePlixRing"
MV=$(sed -nE 's/^MARKETING_VERSION = (.*)$/\1/p' Config/Version.xcconfig)
BUILD=$(sed -nE 's/^CURRENT_PROJECT_VERSION = (.*)$/\1/p' Config/Version.xcconfig)
OUT="build/CarePlixRing-${MV}-${BUILD}"
mkdir -p build
[[ -f Config/Signing.xcconfig ]] || echo "warning: Config/Signing.xcconfig missing — Xcode will need a team selected in Signing & Capabilities" >&2
[[ -f Config/Vendor.xcconfig ]] || echo "note: vendor SDK not linked — this archive is the demo-mode app (run scripts/link-vendor-sdk.sh for the real ring)" >&2
xcodebuild -project CarePlixRing.xcodeproj -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$OUT.xcarchive" archive | tail -5
OPTS=ExportOptions.plist
if [[ "${1:-}" == "--no-upload" ]]; then
  OPTS=build/ExportOptions.local.plist
  sed 's#<string>upload</string>#<string>export</string>#' ExportOptions.plist > "$OPTS"
fi
xcodebuild -exportArchive -archivePath "$OUT.xcarchive" -exportOptionsPlist "$OPTS" -exportPath "$OUT" | tail -5
echo "Done: CarePlix Ring ${MV} (${BUILD}) -> $OUT"
