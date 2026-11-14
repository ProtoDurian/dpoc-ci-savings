#!/usr/bin/env bash
# nix develop .#ci through the Namespace nixcache proxy (cache.nixos.org only via the proxy), attic direct.
set -uo pipefail
subs="http://127.0.0.1:18765 https://attic.primordial.atomi.cloud/primordial https://nix-community.cachix.org https://install.determinate.systems"
t0=$(date +%s.%N)
nix develop .#ci -v --option substituters "$subs" --profile /tmp/ci-profile -c true 2> /tmp/dev.log; rc=$?
echo "T develop=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}') rc=$rc"
grep -oE "copying path '[^']+' from '[^']+'" /tmp/dev.log | sed -E "s/.* from '([^']+)'/\1/" | sort | uniq -c | sed 's/^/FROM /'
grep -iE 'ignoring untrusted|not a trusted|warning' /tmp/dev.log | sort | uniq -c | head -5
