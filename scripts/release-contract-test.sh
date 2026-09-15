#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_SCRIPT="$SCRIPT_DIR/release.sh"

# Test the production predicate without sourcing the release workflow.
eval "$(sed -n '/^has_secure_timestamp() {/,/^}/p' "$RELEASE_SCRIPT")"
has_secure_timestamp $'Authority=Developer ID Application: Example\nTimestamp=2026-09-15 12:00:00'
if has_secure_timestamp $'Timestamp=Not Set'; then
  echo "Timestamp=Not Set was accepted" >&2
  exit 1
fi
if has_secure_timestamp $'Authority=Developer ID Application: Example'; then
  echo "missing timestamp was accepted" >&2
  exit 1
fi

# Keep the appcast command aligned with the installed Sparkle CLI contract.
grep -Fq -- '-o "$APPCAST"' "$RELEASE_SCRIPT"
! grep -Fq -- '--output-path' "$RELEASE_SCRIPT"
grep -Fq -- 'signingCertificate -string "$SIGNING_IDENTITY"' "$RELEASE_SCRIPT"

generate_appcast=""
if [[ -n "${SPARKLE_BIN:-}" && -x "$SPARKLE_BIN/generate_appcast" ]]; then
  generate_appcast="$SPARKLE_BIN/generate_appcast"
else
  generate_appcast="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type f \
    -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' \
    -perm -111 -print -quit 2>/dev/null || true)"
fi
if [[ -n "$generate_appcast" ]]; then
  "$generate_appcast" --help | grep -Fq -- '-o <output-path>'
fi

echo "release contract checks passed"
