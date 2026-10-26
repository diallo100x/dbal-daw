#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if [[ "$(uname -s)" != Darwin ]];then echo 'Apple offline audio tests NOT RUN: macOS required.';exit 0;fi
binary="$(mktemp -t dbal-audio.XXXXXX)"
trap 'rm -f "$binary"' EXIT
xcrun swiftc -O App/Session.swift App/PerformanceModel.swift App/SampleTransform.swift Tests/apple_audio.swift -o "$binary"
"$binary"
