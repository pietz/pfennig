#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build --build-system native --target Agent
xcrun swiftc -parse-as-library -target arm64-apple-macosx27.0 \
  -I .build/arm64-apple-macosx/debug/Modules \
  -I .build/checkouts/GRDB.swift/Sources/GRDBSQLite \
  evals/apple-ai/Probe.swift \
  .build/arm64-apple-macosx/debug/{Core,Agent,GRDB}.build/*.o \
  -lsqlite3 -o /tmp/pfennig-apple-ai-probe
