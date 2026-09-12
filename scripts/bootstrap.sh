#!/usr/bin/env bash
# One-time setup: developer tools, SwiftPM dependencies, Xcode project.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing xcodegen"
  brew install xcodegen
fi

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "==> Installing swiftformat (optional, used by scripts/lint.sh)"
  brew install swiftformat || echo "warning: swiftformat could not be installed; lint.sh will be skipped" >&2
fi

echo "==> Resolving Swift packages"
swift package resolve

echo "==> Generating Ziffer.xcodeproj"
xcodegen generate --quiet

echo "Done. Next: scripts/build.sh, scripts/run.sh, scripts/test.sh"
