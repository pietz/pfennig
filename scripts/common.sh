# Shared settings for all scripts. Sourced, not executed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/Pfennig.xcodeproj"
SCHEME="Pfennig"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$REPO_ROOT/build"
APP_NAME="Pfennig"
if [ "$CONFIGURATION" = Debug ]; then
  APP_NAME="Pfennig Dev"
fi
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
DEVELOPMENT_TEAM="34MWWCL4H2"

# Debug builds are signed with the "Apple Development" identity by its SHA-1,
# so every build carries the same designated requirement and Keychain items
# created by one build stay readable by the next. Ad-hoc signing would give
# each build a new designated requirement and make macOS ask for Keychain
# access again after every rebuild, so a missing identity is an error here
# rather than a silent fallback.
xcodebuild_run() {
  local identity
  identity="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ { print $2; exit }')"
  if [ -z "$identity" ]; then
    echo "error: no 'Apple Development' code signing identity found." >&2
    echo "       Install one in Xcode > Settings > Accounts; ad-hoc signing is not used" >&2
    echo "       because it breaks Keychain access across rebuilds." >&2
    exit 1
  fi
  xcodebuild "$@" \
    CODE_SIGN_STYLE=Manual \
    "CODE_SIGN_IDENTITY=$identity" \
    "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" \
    PROVISIONING_PROFILE_SPECIFIER=""
}

require_project() {
  if [ ! -d "$PROJECT" ]; then
    echo "error: $PROJECT is missing. Run scripts/bootstrap.sh first." >&2
    exit 1
  fi
}
