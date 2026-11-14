#!/usr/bin/env bash
set -euo pipefail

# Stop the MSBuild/Roslyn build servers on exit: left running, they hold the step output open and
# the runner waits 5 s for them before the next step.
trap 'dotnet build-server shutdown >/dev/null 2>&1 || true' EXIT
# ReSharper starts its own MSBuild nodes, which build-server shutdown cannot reach: do not keep nodes alive at all.
export MSBUILDDISABLENODEREUSE=1

./scripts/local/dotnet-dead-code.sh --strict

echo "✅ CI dead-code inspection complete"
