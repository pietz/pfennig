#!/usr/bin/env bash
# Opt-in live acceptance: synthetic files only, temporary database, paid API calls.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

PFENNIG_LIVE_ACCEPTANCE=1 swift test --filter LiveAcceptanceTests
