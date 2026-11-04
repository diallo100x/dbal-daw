#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${VII_BUILD_DIR:-/tmp/dbal-vii-core}"
mkdir -p "$OUT"
cc -std=c11 -O2 -Wall -Wextra "$ROOT/Core/VIIEngine.c" "$ROOT/Tests/vii_smoke.c" -lm -o "$OUT/vii_smoke"
"$OUT/vii_smoke"
