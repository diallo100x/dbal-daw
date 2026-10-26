#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
args=(-project DBALPocketStudio.xcodeproj -scheme DBALNativeMac -configuration Release -destination 'platform=macOS' -derivedDataPath Build)
if [[ -n "${1:-}" ]];then args+=("DEVELOPMENT_TEAM=$1" -allowProvisioningUpdates);fi
xcodebuild "${args[@]}" build
echo 'Built: Build/Build/Products/Release/DBALNativeMac.app'
