#!/usr/bin/env bash
set -euo pipefail

command -v hello >/dev/null && echo "@@HELLO present" || echo "@@HELLO absent"
bun install --frozen-lockfile
./scripts/local/build.sh
