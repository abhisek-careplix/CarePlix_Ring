#!/usr/bin/env bash
# Enable the real ring on device builds by pointing the app at the licensed Veepoo frameworks.
#   scripts/link-vendor-sdk.sh /path/to/Frameworks     # a folder containing VeepooBleSDK.framework etc.
# Copies the frameworks into ios/Frameworks (git-ignored) and writes Config/Vendor.xcconfig (git-ignored).
# Without this step the app builds and archives in demo mode (realistic sample data, no Bluetooth).
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:?usage: link-vendor-sdk.sh <folder with VeepooBleSDK.framework>}"
[[ -d "$SRC/VeepooBleSDK.framework" ]] || { echo "VeepooBleSDK.framework not found in $SRC" >&2; exit 1; }
mkdir -p ../Frameworks
rsync -a --delete "$SRC"/*.framework ../Frameworks/
FLAGS="\$(inherited) -ObjC"
for fw in ../Frameworks/*.framework; do FLAGS="$FLAGS -framework $(basename "$fw" .framework)"; done
cat > Config/Vendor.xcconfig <<XC
// Written by scripts/link-vendor-sdk.sh on $(date -u +%Y-%m-%dT%H:%MZ). Do not commit.
FRAMEWORK_SEARCH_PATHS = \$(inherited) \$(PROJECT_DIR)/../Frameworks
OTHER_LDFLAGS[sdk=iphoneos*] = $FLAGS
SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphoneos*] = \$(inherited) VEEPOO
XC
echo "Linked: $(ls ../Frameworks | tr '\n' ' ')"
echo "Device builds now use the real ring. Simulator builds stay in demo mode (the vendor SDK has no simulator slice)."
