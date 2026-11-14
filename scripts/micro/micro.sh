#!/usr/bin/env bash
# Times the pieces of a dev-shell evaluation on a Namespace runner. Prints "TIME <label> <s> rc=<rc>".
set -uo pipefail
export ATOMI_DEVENV_CACHE=1
T="$(mktemp -d)"
sys="$(nix config show system)"
t() {
  local label="$1" s e rc=0
  shift
  s=$EPOCHREALTIME
  "$@" >"$T/out.$label" 2>"$T/err.$label" || rc=$?
  e=$EPOCHREALTIME
  printf 'TIME %s %.2f rc=%s\n' "$label" "$(echo "$e - $s" | bc)" "$rc"
  [ "$rc" = 0 ] || tail -n 5 "$T/err.$label"
}
echo "B_HIT=${B_HIT:-} inputs=$(nix flake metadata --json 2>/dev/null | jq '.locks.nodes|length')"
ls -la /tmp/b-devenv 2>/dev/null || true
# --- 1. pure evaluation, first in this commit (fresh rev: the eval cache cannot hit) and again
t eval_ci_drv_first nix eval --raw ".#devShells.$sys.ci.drvPath"
t eval_ci_drv_again nix eval --raw ".#devShells.$sys.ci.drvPath"
t eval_cd_drv_first nix eval --raw ".#devShells.$sys.cd.drvPath"
t eval_ci_noevalcache nix eval --no-eval-cache --raw ".#devShells.$sys.ci.drvPath"
t eval_ci_noevalcache_nolazy nix eval --no-eval-cache --option lazy-trees false --raw ".#devShells.$sys.ci.drvPath"
# --- 2. what the jobs run
t printdevenv_ci nix print-dev-env .#ci
t printdevenv_cd nix print-dev-env .#cd
t develop_ci nix develop .#ci -c true
t develop_cd nix develop .#cd -c true
# --- 3. profile / pinned store path: no evaluation at all
t develop_profile_create nix develop --profile "$T/p-ci" .#ci -c true
t develop_profile_reuse nix develop "$T/p-ci" -c true
pin="$(readlink -f "$T/p-ci")"
echo "pinned env path: $pin"
t develop_pinned_path nix develop "$pin" -c true
t develop_pinned_path_again nix develop "$pin" -c true
nix develop --profile "$T/p-cd" .#cd -c true >/dev/null 2>&1
# --- 4. content-addressed copy of just the flake inputs: eval cache keyed on content, so it
#        survives new commits (persisted ~/.cache/nix on the volume)
d="$HOME/atomi-devflake"
rm -rf "$d" && mkdir -p "$d" && cp -a flake.nix flake.lock nix "$d/"
t pathflake_printdevenv_1 nix print-dev-env "path:$d#ci"
t pathflake_printdevenv_2 nix print-dev-env "path:$d#ci"
t pathflake_develop nix develop "path:$d#ci" -c true
t pathflake_eval_drv nix eval --raw "path:$d#devShells.$sys.ci.drvPath"
# --- 5. atomi-develop miss, step by step (PS4 timestamps)
export ATOMI_DEVENV_DIR="$T/ad"
PS4='+ $EPOCHREALTIME ' t atomi_miss_cd bash -x "$(command -v atomi-develop)" .#cd -c true
grep -E '^\++ [0-9.]+ (nix|mktemp|git|cp|tar|sed|find|mv)' "$T/err.atomi_miss_cd" | awk '{print $2, $3, $4, $5, $6, $7}' >"$T/trace"
awk 'NR>1{printf "STEP %.2f %s\n", $1-p, prev} {p=$1; prev=$0}' "$T/trace" | sort -k2 -nr | head -15
t atomi_hit_cd atomi-develop .#cd -c true
t atomi_warm_both atomi-develop --warm .#ci .#cd
# --- 6. GitHub Actions cache copy for (b): save what this run evaluated
mkdir -p /tmp/b-devenv && cp -a "$T/ad/." /tmp/b-devenv/ 2>/dev/null || true
# --- 7. closure sizes
for p in p-ci p-cd; do echo "closure $p: $(nix path-info -S "$T/$p" | awk '{printf "%.2f GB", $2/1e9}') paths=$(nix path-info -r "$T/$p" | wc -l)"; done
echo "closure union: $(nix path-info -r "$T/p-ci" "$T/p-cd" | sort -u | xargs nix path-info -s | awk '{s+=$2} END {printf "%.2f GB", s/1e9}')"
echo "cd minus ci paths: $(comm -13 <(nix path-info -r "$T/p-ci" | sort) <(nix path-info -r "$T/p-cd" | sort) | wc -l)"
comm -13 <(nix path-info -r "$T/p-ci" | sort) <(nix path-info -r "$T/p-cd" | sort) | head
