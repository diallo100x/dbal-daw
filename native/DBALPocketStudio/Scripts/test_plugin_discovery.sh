#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Apple Audio Unit discovery tests NOT RUN: requires macOS SDK.'
  exit 0
fi
directory="$(mktemp -d -t dbal-discovery.XXXXXX)"
trap 'rm -rf "$directory"' EXIT
cp Tests/plugin_discovery.swift "$directory/main.swift"
swiftc App/Session.swift App/PerformanceModel.swift App/PluginDiscovery.swift "$directory/main.swift" -o "$directory/test"
"$directory/test"
