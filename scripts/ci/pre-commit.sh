#!/usr/bin/env bash
set -euo pipefail

# The CI shell installs no git hooks; it hands the generated hook config in
# PRE_COMMIT_CONFIG_FILE. Pass it with --config (no link left in the worktree,
# so a later developer shell still installs its hooks).
config=()
if [ -n "${PRE_COMMIT_CONFIG_FILE:-}" ]; then
  config=(--config "${PRE_COMMIT_CONFIG_FILE}")
fi

bun install --frozen-lockfile
pre-commit run "${config[@]}" --all-files --show-diff-on-failure

echo "✅ Pre-commit gates passed"
