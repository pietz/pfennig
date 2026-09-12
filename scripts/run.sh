#!/usr/bin/env bash
# Builds and launches the app. No Xcode required.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

"$REPO_ROOT/scripts/build.sh"

echo "==> Launching Ziffer"
open "$APP_PATH"
