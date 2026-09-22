#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination="${1:-platform=iOS Simulator,name=iPhone Duo}"
swift test
python3 ci_scripts/fixture_server.py > /tmp/monkeytail-fixtures.log 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
sleep 0.5
if ! kill -0 "$fixture_pid" 2>/dev/null; then
  cat /tmp/monkeytail-fixtures.log
  exit 1
fi
xcodebuild -scheme Monkeytail -destination "$destination" \
  -derivedDataPath build -parallel-testing-enabled NO \
  test CODE_SIGNING_ALLOWED=NO
