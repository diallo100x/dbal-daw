#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
flavor="${1:-Legacy}"
platform="${2:-ios}"
if [[ "$flavor" != Legacy && "$flavor" != Pro ]]; then echo 'Usage: Scripts/build.sh Legacy|Pro ios|simulator|mac [TEAM_ID]'; exit 2; fi
if ! command -v xcodebuild >/dev/null; then echo 'Install/select full Xcode first.'; exit 1; fi
args=(-project DBALPocketStudio.xcodeproj -scheme "Pocket$flavor" -configuration Release -derivedDataPath Build)
case "$platform" in
 ios) args+=(-destination 'generic/platform=iOS');;
 simulator) args+=(-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO);;
 mac) args+=(-destination 'generic/platform=macOS,variant=Mac Catalyst');;
 *) echo 'Choose ios, simulator, or mac.';exit 2;;
esac
if [[ -n "${3:-}" ]];then args+=("DEVELOPMENT_TEAM=$3" -allowProvisioningUpdates);fi
xcodebuild "${args[@]}" build
