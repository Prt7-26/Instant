#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEVELOPER_PATH="$(xcode-select -p)"
FRAMEWORK_PATH="$DEVELOPER_PATH/Library/Developer/Frameworks"
if [ -d "$FRAMEWORK_PATH/Testing.framework" ]; then
  swift test --build-system native -Xswiftc -F -Xswiftc "$FRAMEWORK_PATH" -Xlinker -rpath -Xlinker "$FRAMEWORK_PATH" "$@"
else
  swift test --build-system native "$@"
fi
