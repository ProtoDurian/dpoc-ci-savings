#!/usr/bin/env bash
set -euo pipefail

# The CI shell installs no git hooks; link the generated hook config here instead.
if [ -n "${PRE_COMMIT_CONFIG_FILE:-}" ]; then
  ln -fs "${PRE_COMMIT_CONFIG_FILE}" .pre-commit-config.yaml
fi

bun install --frozen-lockfile
pre-commit run --all-files --show-diff-on-failure

echo "✅ Pre-commit gates passed"
