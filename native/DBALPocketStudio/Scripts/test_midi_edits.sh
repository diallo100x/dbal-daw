#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if ! command -v swiftc >/dev/null;then echo 'Swift compiler unavailable: MIDI editor logic tests NOT RUN.';exit 0;fi
directory="$(mktemp -d -t dbal-midi-edits.XXXXXX)"
binary="$directory/test"
cp Tests/midi_note_edits.swift "$directory/main.swift"
trap 'rm -rf "$directory"' EXIT
swiftc App/Session.swift App/PerformanceModel.swift App/MIDINoteEdits.swift "$directory/main.swift" -o "$binary"
"$binary"
