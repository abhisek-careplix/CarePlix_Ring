#!/usr/bin/env bash
# Bump the build number (and optionally the marketing version) in Config/Version.xcconfig.
#   scripts/bump-version.sh              -> build +1
#   scripts/bump-version.sh 1.1.0        -> version 1.1.0, build +1
#   scripts/bump-version.sh 1.1.0 --tag  -> also creates git tag ring-v1.1.0-<build>
set -euo pipefail
cd "$(dirname "$0")/.."
FILE=Config/Version.xcconfig
VERSION="${1:-}"; TAG="${2:-}"
BUILD=$(sed -nE 's/^CURRENT_PROJECT_VERSION = ([0-9]+)$/\1/p' "$FILE")
NEXT=$((BUILD + 1))
sed -i '' -E "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${NEXT}/" "$FILE"
if [[ -n "$VERSION" && "$VERSION" != "--tag" ]]; then
  sed -i '' -E "s/^MARKETING_VERSION = .*/MARKETING_VERSION = ${VERSION}/" "$FILE"
fi
MV=$(sed -nE 's/^MARKETING_VERSION = (.*)$/\1/p' "$FILE")
echo "CarePlix Ring ${MV} (${NEXT})"
if [[ "$VERSION" == "--tag" || "$TAG" == "--tag" ]]; then
  git add "$FILE" && git commit -m "Bump CarePlix Ring to ${MV} (${NEXT})" && git tag "ring-v${MV}-${NEXT}"
  echo "tagged ring-v${MV}-${NEXT}"
fi
