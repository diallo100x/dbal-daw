#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
python3 Tests/project_tests.py
binary="$(mktemp -t pocket-sampler.XXXXXX)"
trap 'rm -f "$binary"' EXIT
cc -std=c11 -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined -fno-omit-frame-pointer -g Engine/PocketSampler.c Tests/sampler_tests.c -lm -pthread -o "$binary"
ASAN_OPTIONS=detect_leaks=0 "$binary"
cc -std=c11 -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined -fno-omit-frame-pointer -g Engine/PocketFX.c Tests/fx_tests.c -lm -o "$binary"
ASAN_OPTIONS=detect_leaks=0 "$binary"

./Scripts/test_clip_edits.sh
