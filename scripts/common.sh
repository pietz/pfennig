# Shared settings for all scripts. Sourced, not executed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/Pfennig.xcodeproj"
SCHEME="Pfennig"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$REPO_ROOT/build"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Pfennig.app"
DEVELOPMENT_TEAM="34MWWCL4H2"

# Debug builds are signed with the "Apple Development" identity so that
# Keychain items survive rebuilds; ad-hoc signing is the fallback.
xcodebuild_run() {
  local identity
  identity="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ { print $2; exit }')"
  if [ -z "$identity" ]; then
    echo "note: no Apple Development identity found, falling back to ad-hoc signing" >&2
    identity="-"
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
