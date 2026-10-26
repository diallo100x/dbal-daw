#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
pocket_root="$PWD"
flavor="${1:-Legacy}"
if [[ "$flavor" != Legacy && "$flavor" != Pro ]];then echo 'Choose Legacy or Pro.';exit 2;fi
if ! command -v xcodebuild >/dev/null;then echo 'Full Xcode is required.';exit 1;fi
mkdir -p Build
xcodebuild -project DBALPocketStudio.xcodeproj -scheme "Pocket$flavor" -configuration Release -destination 'generic/platform=iOS' -derivedDataPath Build CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "Build/Pocket$flavor-build.log"
staging="$(mktemp -d -t pocket-ipa.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Payload"
/usr/bin/ditto "Build/Build/Products/Release-iphoneos/Pocket$flavor.app" "$staging/Payload/Pocket$flavor.app"
ipa="$pocket_root/Build/Pocket$flavor-0.1.4-unsigned.ipa"
/usr/bin/ditto -c -k --norsrc --keepParent "$staging/Payload" "$ipa"
open -R "$ipa"
echo "Unsigned IPA ready: $ipa"
echo 'Use the same Sideloadly account and bundle-ID settings as your working installation.'
