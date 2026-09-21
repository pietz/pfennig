#!/usr/bin/env bash
# Builds Pfennig Dev (Debug) or Pfennig (Release) into build/Build/Products/.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

xcodegen generate --quiet

xcodebuild_run \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  build

echo "Built $APP_PATH"
