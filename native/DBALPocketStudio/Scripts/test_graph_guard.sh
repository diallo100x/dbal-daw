#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if [[ "$(uname -s)" != Darwin ]];then echo 'Audio graph guard tests NOT RUN: macOS required.';exit 0;fi
binary="$(mktemp -t dbal-graph.XXXXXX)"
trap 'rm -f "$binary"' EXIT
xcrun clang -fobjc-arc -fobjc-exceptions -Wall -Wextra -Werror -framework Foundation -framework AVFoundation Engine/AudioGraphGuard.m Tests/graph_guard_tests.m -o "$binary"
"$binary"
