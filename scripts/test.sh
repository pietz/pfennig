#!/usr/bin/env bash
# Runs the Swift Testing suites of all packages.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

swift test "$@"
