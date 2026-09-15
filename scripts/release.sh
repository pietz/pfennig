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
# The default profile name still says "ziffer": it references an existing local
# Keychain item created before the rename to Pfennig. Renaming it here would
# break notarization until the credentials are stored again. Override
# NOTARY_PROFILE in the environment to use a differently named profile.
NOTARY_PROFILE="${NOTARY_PROFILE:-ziffer-notary}"
ARCHIVE_PATH="$DERIVED_DATA/Pfennig.xcarchive"
ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/Pfennig.app"
EXPORT_PATH="$DERIVED_DATA/Pfennig-export"
EXPORT_OPTIONS="$DERIVED_DATA/Pfennig-ExportOptions.plist"
EXPORTED_APP="$EXPORT_PATH/Pfennig.app"
DIST_DIR="$REPO_ROOT/dist"
SUBMISSION_ZIP="$DIST_DIR/Pfennig-notarization.zip"
NOTARY_RESULT="$DIST_DIR/notary-result.json"
NOTARY_LOG="$DIST_DIR/notary-log.json"
UPDATE_ZIP=""
UPDATE_CHECKSUM=""
APPCAST="$DIST_DIR/appcast.xml"
APPCAST_CHECKSUM="$APPCAST.sha256"
SPARKLE_BIN="${SPARKLE_BIN:-}"

validate_sparkle_configuration() {
  local plist_path="${1:-$REPO_ROOT/App/Info.plist}"
  local feed_url public_key
  feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist_path" 2>/dev/null || true)"
  public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist_path" 2>/dev/null || true)"

  if [[ "$feed_url" != https://* ]]; then
    echo "error: App/Info.plist must contain an HTTPS SUFeedURL" >&2
    exit 1
  fi
  if [[ -z "$public_key" || "$public_key" == *'$('* ]]; then
    echo "error: App/Info.plist is missing SUPublicEDKey; owner must run Sparkle generate_keys and embed the public key" >&2
    exit 1
  fi
}

require_sparkle_tools() {
  if [[ -z "$SPARKLE_BIN" || ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "error: Sparkle tools not found; set SPARKLE_BIN to the official Sparkle/bin directory" >&2
    exit 1
  fi
}

package_release() {
  local output_zip="$1"
  local package_dir="$DIST_DIR/Pfennig-$VERSION"
  rm -rf "$package_dir"
  mkdir -p "$package_dir"
  ditto "$EXPORTED_APP" "$package_dir/Pfennig.app"
  cp "$REPO_ROOT/LICENSE" "$package_dir/LICENSE.txt"
  cp "$REPO_ROOT/docs/privacy.md" "$package_dir/PRIVACY.md"
  ditto -c -k --keepParent "$package_dir" "$output_zip"
  rm -rf "$package_dir"
}

package_update() {
  local output_zip="$1"
  rm -f "$output_zip"
  # We intentionally use an app-only update archive following Sparkle’s
  # recommendation. Keep the public distribution archive above unchanged.
  ditto -c -k --sequesterRsrc --keepParent "$EXPORTED_APP" "$output_zip"
}

has_secure_timestamp() {
  local details="$1"
  grep -Eq '^Timestamp=' <<<"$details" \
    && ! grep -Fq 'Timestamp=Not Set' <<<"$details"
}

validate_sparkle_helpers() {
  local app_path="$1"
  local relative_path helper_path details
  local helper_paths=(
    "Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
    "Sparkle.framework/Versions/B/Autoupdate"
    "Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
    "Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  )

  for relative_path in "${helper_paths[@]}"; do
    helper_path="$app_path/Contents/Frameworks/$relative_path"
    if [[ ! -x "$helper_path" ]]; then
      echo "error: Sparkle helper is missing or not executable: $relative_path" >&2
      exit 1
    fi
    if ! details="$(codesign --display --verbose=4 "$helper_path" 2>&1)"; then
      echo "error: cannot inspect Sparkle helper signature: $relative_path" >&2
      printf '%s\n' "$details" >&2
      exit 1
    fi
    if grep -Fq 'Signature=adhoc' <<<"$details" \
      || ! grep -Fq 'Authority=Developer ID Application:' <<<"$details" \
      || ! grep -Fq "TeamIdentifier=$TEAM_ID" <<<"$details"; then
      echo "error: Sparkle helper is not signed by Developer ID team $TEAM_ID: $relative_path" >&2
      printf '%s\n' "$details" >&2
      exit 1
    fi
    if ! has_secure_timestamp "$details"; then
      echo "error: Sparkle helper has no secure timestamp: $relative_path" >&2
      printf '%s\n' "$details" >&2
      exit 1
    fi
    if ! codesign --verify --strict --verbose=2 "$helper_path"; then
      echo "error: Sparkle helper signature verification failed: $relative_path" >&2
      exit 1
    fi
  done
}

generate_update_feed() {
  local generator="$SPARKLE_BIN/generate_appcast"
  local input_dir="$DIST_DIR/sparkle-updates"
  local download_prefix="https://github.com/pietz/pfennig/releases/download/v$VERSION/"
  local build_number

  require_sparkle_tools

  build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXPORTED_APP/Contents/Info.plist")"
  rm -rf "$input_dir"
  mkdir -p "$input_dir"
  cp "$UPDATE_ZIP" "$input_dir/"
  rm -f "$APPCAST"

  "$generator" \
    --download-url-prefix "$download_prefix" \
    --link "https://github.com/pietz/pfennig/releases/tag/v$VERSION" \
    --maximum-deltas 0 \
    -o "$APPCAST" \
    "$input_dir"

  rm -rf "$input_dir"
  if [[ ! -s "$APPCAST" ]]; then
    echo "error: Sparkle did not create $APPCAST" >&2
    exit 1
  fi
  if ! grep -Fq 'sparkle:edSignature=' "$APPCAST"; then
    echo "error: generated appcast has no EdDSA update signature" >&2
    exit 1
  fi
  if ! grep -Fq "<sparkle:version>$build_number</sparkle:version>" "$APPCAST"; then
    echo "error: appcast version does not match CFBundleVersion ($build_number)" >&2
    exit 1
  fi
  if ! grep -Fq "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$APPCAST"; then
    echo "error: appcast version does not match CFBundleShortVersionString ($VERSION)" >&2
    exit 1
  fi
}

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "error: signing identity not found: $SIGNING_IDENTITY" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required; run scripts/bootstrap.sh first" >&2
  exit 1
fi

if [[ "$MODE" == "--notarize" ]]; then
  validate_sparkle_configuration
  require_sparkle_tools
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
fi

xcodegen generate --quiet
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$DIST_DIR"
rm -f "$SUBMISSION_ZIP" "$NOTARY_RESULT" "$NOTARY_LOG"

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

/usr/bin/plutil -create xml1 "$EXPORT_OPTIONS"
/usr/bin/plutil -insert method -string developer-id "$EXPORT_OPTIONS"
/usr/bin/plutil -insert signingStyle -string manual "$EXPORT_OPTIONS"
/usr/bin/plutil -insert signingCertificate -string "$SIGNING_IDENTITY" "$EXPORT_OPTIONS"
/usr/bin/plutil -insert teamID -string "$TEAM_ID" "$EXPORT_OPTIONS"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

if [[ ! -d "$EXPORTED_APP" ]]; then
  echo "error: exported app not found at $EXPORTED_APP" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP"
validate_sparkle_helpers "$EXPORTED_APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXPORTED_APP/Contents/Info.plist")"
if [[ "$MODE" == "--notarize" ]]; then
  validate_sparkle_configuration "$EXPORTED_APP/Contents/Info.plist"
fi
if [[ "$MODE" == "--build-only" ]]; then
  FINAL_ZIP="$DIST_DIR/Pfennig-$VERSION-macOS-signed-unnotarized.zip"
else
  FINAL_ZIP="$DIST_DIR/Pfennig-$VERSION-macOS.zip"
fi
CHECKSUM="$FINAL_ZIP.sha256"
rm -f "$FINAL_ZIP" "$CHECKSUM"

ditto -c -k --keepParent "$EXPORTED_APP" "$SUBMISSION_ZIP"

if [[ "$MODE" == "--build-only" ]]; then
  rm -f "$SUBMISSION_ZIP"
  package_release "$FINAL_ZIP"
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
  SUBMISSION_ID="$(plutil -extract id raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"
  if [[ -z "$SUBMISSION_ID" ]]; then
    echo "warning: no submission id was returned; cannot download Apple's notarization log" >&2
  elif xcrun notarytool log "$SUBMISSION_ID" \
    --keychain-profile "$NOTARY_PROFILE" "$NOTARY_LOG" \
    && [[ -s "$NOTARY_LOG" ]]; then
    echo "Apple notarization log: $NOTARY_LOG" >&2
  else
    echo "warning: could not download Apple's notarization log to $NOTARY_LOG" >&2
  fi
  cat "$NOTARY_RESULT" >&2
  exit 1
fi

xcrun stapler staple "$EXPORTED_APP"
xcrun stapler validate "$EXPORTED_APP"
codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP"
spctl --assess --type execute --verbose=4 "$EXPORTED_APP"

UPDATE_ZIP="$DIST_DIR/Pfennig-$VERSION-macOS-update.zip"
UPDATE_CHECKSUM="$UPDATE_ZIP.sha256"
rm -f "$UPDATE_ZIP" "$UPDATE_CHECKSUM" "$APPCAST" "$APPCAST_CHECKSUM"
package_release "$FINAL_ZIP"
package_update "$UPDATE_ZIP"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$FINAL_ZIP")" > "$(basename "$CHECKSUM")")
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$UPDATE_ZIP")" > "$(basename "$UPDATE_CHECKSUM")")
generate_update_feed
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$APPCAST")" > "$(basename "$APPCAST_CHECKSUM")")
rm -f "$SUBMISSION_ZIP"

echo "Notarized release: $FINAL_ZIP"
echo "Sparkle update: $UPDATE_ZIP"
echo "Sparkle appcast: $APPCAST"
echo "Checksums: $CHECKSUM, $UPDATE_CHECKSUM, $APPCAST_CHECKSUM"
