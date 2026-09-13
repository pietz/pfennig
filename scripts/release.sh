#!/usr/bin/env bash
# Builds a Developer ID signed release. Pass --notarize to submit it to Apple,
# staple the ticket, and produce the distributable ZIP.
set -euo pipefail

CONFIGURATION=Release
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

MODE="${1:---build-only}"
if [[ "$MODE" != "--build-only" && "$MODE" != "--notarize" ]]; then
  echo "usage: scripts/release.sh [--build-only|--notarize]" >&2
  exit 2
fi

TEAM_ID="${TEAM_ID:-34MWWCL4H2}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Paul-Louis Pröve ($TEAM_ID)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ziffer-notary}"
ARCHIVE_PATH="$DERIVED_DATA/Ziffer.xcarchive"
ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/Ziffer.app"
DIST_DIR="$REPO_ROOT/dist"
SUBMISSION_ZIP="$DIST_DIR/Ziffer-notarization.zip"
NOTARY_RESULT="$DIST_DIR/notary-result.json"

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "error: signing identity not found: $SIGNING_IDENTITY" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required; run scripts/bootstrap.sh first" >&2
  exit 1
fi

if [[ "$MODE" == "--notarize" ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
fi

xcodegen generate --quiet
rm -rf "$ARCHIVE_PATH"
mkdir -p "$DIST_DIR"
rm -f "$SUBMISSION_ZIP" "$NOTARY_RESULT"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=$SIGNING_IDENTITY" \
  "DEVELOPMENT_TEAM=$TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER= \
  OTHER_CODE_SIGN_FLAGS=--timestamp

if [[ ! -d "$ARCHIVED_APP" ]]; then
  echo "error: archived app not found at $ARCHIVED_APP" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$ARCHIVED_APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ARCHIVED_APP/Contents/Info.plist")"
if [[ "$MODE" == "--build-only" ]]; then
  FINAL_ZIP="$DIST_DIR/Ziffer-$VERSION-macOS-signed-unnotarized.zip"
else
  FINAL_ZIP="$DIST_DIR/Ziffer-$VERSION-macOS.zip"
fi
CHECKSUM="$FINAL_ZIP.sha256"
rm -f "$FINAL_ZIP" "$CHECKSUM"

ditto -c -k --keepParent "$ARCHIVED_APP" "$SUBMISSION_ZIP"

if [[ "$MODE" == "--build-only" ]]; then
  mv "$SUBMISSION_ZIP" "$FINAL_ZIP"
  (cd "$DIST_DIR" && shasum -a 256 "$(basename "$FINAL_ZIP")" > "$(basename "$CHECKSUM")")
  echo "Built signed, non-notarized archive: $FINAL_ZIP"
  exit 0
fi

xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_RESULT"

STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT")"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "error: Apple notarization status is $STATUS" >&2
  cat "$NOTARY_RESULT" >&2
  exit 1
fi

xcrun stapler staple "$ARCHIVED_APP"
xcrun stapler validate "$ARCHIVED_APP"
codesign --verify --deep --strict --verbose=2 "$ARCHIVED_APP"
spctl --assess --type execute --verbose=4 "$ARCHIVED_APP"

ditto -c -k --keepParent "$ARCHIVED_APP" "$FINAL_ZIP"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$FINAL_ZIP")" > "$(basename "$CHECKSUM")")
rm -f "$SUBMISSION_ZIP"

echo "Notarized release: $FINAL_ZIP"
echo "Checksum: $CHECKSUM"
