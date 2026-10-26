#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if ! command -v swiftc >/dev/null;then
  echo 'Swift compiler unavailable: clip-edit Swift tests NOT RUN.'
  exit 0
fi
binary="$(mktemp -t pocket-clips.XXXXXX)"
trap 'rm -f "$binary"' EXIT
swiftc App/Session.swift App/PerformanceModel.swift App/MIDIMessage.swift App/ClipEdits.swift Tests/clip_edits.swift -o "$binary"
"$binary"
