#!/usr/bin/env bash
# Builds the app bundle into build/Build/Products/<Configuration>/Pfennig.app
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

if [ ! -d "$PROJECT" ]; then
  xcodegen generate --quiet
fi

xcodebuild_run \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  build

echo "Built $APP_PATH"
