#!/usr/bin/env bash
# Formats Swift sources in place. Optional: nothing depends on swiftformat.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "swiftformat is not installed - skipping. Run scripts/bootstrap.sh to install it." >&2
  exit 0
fi

swiftformat App Sources Tests
