#!/usr/bin/env bash
# dpoc-ovh: does a durian-shell hit really run the cached env? old (v3.9.1+nsmac) vs fixed copy.
# usage: ovh-diag.sh <devshell-name>
set -uo pipefail
sh="$1"
d() { awk -v a="$1" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.3f", b-a}'; }
probe='echo "DIAG cc=${CC:-none} first=${PATH%%:*}"'
export DURIAN_SHELL_CACHE=1 DURIAN_SHELL_DIR=/nix/durian-shell
echo "DIAG xargs-r: $(echo | xargs -r echo ok 2>&1)"
tools="$(nix develop ".#$sh" -c bash -c 'for t in find sed grep sha256sum; do dirname "$(command -v $t)"; done' | sort -u | tr '\n' ':')"
fixed="$(command -v durian-shell)"
for v in old-gnu fixed-bsd fixed-gnu; do
  case "$v" in
  old-gnu) ds="$PWD/scripts/ci/durian-old"; P="$tools$PATH" ;;
  fixed-bsd) ds="$fixed"; P="$PATH" ;;
  fixed-gnu) ds="$fixed"; P="$tools$PATH" ;;
  esac
  export DURIAN_SHELL_SCOPE="diag-$v"
  for i in 1 2 3; do
    t=$EPOCHREALTIME
    out="$(PATH="$P" "$ds" ".#$sh" -c bash -c "$probe" 2>&1)"
    echo "DIAG $v call$i $(d "$t")s :: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
  done
  PATH="$P" bash -x "$ds" ".#$sh" -c true 2>&1 | rg -o 'bash_bin=\S*|src=\S*|\+ plain|exec nix develop' | sort | uniq -c | tr '\n' ' ' | sed "s/^/DIAG $v trace: /"; echo
done
t=$EPOCHREALTIME; out="$(nix develop ".#$sh" -c bash -c "$probe")"; echo "DIAG plain-nix-develop $(d "$t")s :: $out"
exit 0
