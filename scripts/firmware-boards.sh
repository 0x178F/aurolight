#!/usr/bin/env bash
set -euo pipefail
grep -oE '^\[env:[^]]+' "$(dirname "$0")/../firmware/platformio.ini" | cut -d: -f2
