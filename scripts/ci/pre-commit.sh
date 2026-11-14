#!/usr/bin/env bash
set -euo pipefail

# Stop the MSBuild/Roslyn build servers on exit: left running, they hold the step output open and
# the runner waits 5 s for them before the next step.
trap 'dotnet build-server shutdown >/dev/null 2>&1 || true' EXIT

dotnet restore dotnet-base.slnx
pre-commit run --all-files --show-diff-on-failure

echo "✅ Pre-commit gates passed"
