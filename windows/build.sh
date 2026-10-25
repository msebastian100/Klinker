#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 gen_levels.py
zig cc -std=c11 -Wall -Wextra -O2 -o /tmp/klinker-test test.c game.c levels.c -lm
/tmp/klinker-test
mkdir -p ../dist
zig cc -std=c11 -O2 -target x86_64-windows-gnu -o "../dist/Klinker.exe" win.c game.c levels.c \
  -lgdi32 -luser32 -lwinmm -lkernel32 \
  -Wl,--subsystem,windows
