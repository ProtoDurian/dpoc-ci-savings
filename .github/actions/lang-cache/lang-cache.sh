#!/usr/bin/env bash
# lang-cache.sh <restore|save>
# Package/build caches in Namespace Artifacts (object storage), never on a cache volume.
#   LC_NAME          cache name, e.g. go, nuget, pub, gradle, bun
#   LC_PATHS         newline-separated paths (~ and workspace-relative allowed)
#   LC_KEY_FILES     newline-separated git pathspec globs whose contents form the key (e.g. **/go.sum)
#   LC_KEY_EXTRA     extra key text (tool version, OS, week number...)
#   LC_WRITE_BRANCH  only jobs on this branch upload (default: main); every other ref is restore-only
#   LC_EXPIRES       artifact lifetime (default 720h)
# Keys: lang-cache/<owner-repo>/<name>/<hash>.tzst (exact) and .../latest-<branch>.tzst (fallback).
# Never fails the job: any error means "cold", with a ::warning::.
set -uo pipefail
mode=${1:?restore|save}
name=${LC_NAME:?}
ws=${GITHUB_WORKSPACE:-$PWD}
branch=${LC_WRITE_BRANCH:-main}
ref=${GITHUB_REF_NAME:-local}
scope=$(echo "${GITHUB_REPOSITORY:-local/local}" | tr '[:upper:]/_' '[:lower:]--')
state="${RUNNER_TEMP:-/tmp}/lang-cache-$name.state"
now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN{printf "%.2f", b-a}'; }
log() { echo "[lang-cache:$name] $*"; }

if ! command -v nsc >/dev/null 2>&1 || { [ -z "${NSC_TOKEN_FILE:-}" ] && [ -z "${LC_FORCE:-}" ]; }; then
  log "no Namespace credentials on this runner: cache off (job continues cold)"
  exit 0
fi

paths=()
while IFS= read -r p; do
  [ -z "$p" ] && continue
  p="${p/#\~/$HOME}"
  [[ $p != /* ]] && p="$ws/$p"
  paths+=("$p")
done <<<"${LC_PATHS:-}"

key_hash() {
  local specs=()
  while IFS= read -r g; do [ -n "$g" ] && specs+=(":(glob)$g"); done <<<"${LC_KEY_FILES:-}"
  {
    printf '%s\n' "${LC_KEY_EXTRA:-}" "$(uname -sm)"
    if [ ${#specs[@]} -gt 0 ]; then git -C "$ws" ls-files -z -- "${specs[@]}" | sort -z | xargs -0 -r -I{} sh -c 'echo "== {}"; cat "{}"'; fi
  } | sha256sum | cut -c1-16
}

base="lang-cache/$scope/$name"
hash=$(key_hash)
exact="$base/$hash.tzst"
latest="$base/latest-$branch.tzst"
tmp="${RUNNER_TEMP:-/tmp}/lang-cache-$name.tzst"

case $mode in
  restore)
    t0=$(now); hit=miss
    if nsc artifact download "$exact" "$tmp" >/dev/null 2>&1; then hit=exact
    elif nsc artifact download "$latest" "$tmp" >/dev/null 2>&1; then hit=fallback
    fi
    if [ "$hit" != miss ]; then
      size=$(du -m "$tmp" | cut -f1)
      if ! tar -I zstd -xf "$tmp" -C / 2>/dev/null; then
        echo "::warning::lang-cache $name: could not unpack $hit cache; continuing cold"; hit=miss
      fi
      rm -f "$tmp"
      log "restore $hit key=$hash ${size}MB in $(since "$t0")s"
    else
      log "restore miss key=$hash in $(since "$t0")s"
    fi
    echo "$hit $hash" >"$state"
    ;;
  save)
    t0=$(now)
    read -r hit oldhash <"$state" 2>/dev/null || { hit=miss; oldhash=; }
    if [ "$ref" != "$branch" ]; then log "save skipped: restore-only on $ref (writer branch: $branch)"; exit 0; fi
    if [ "$hit" = exact ] && [ "$oldhash" = "$hash" ]; then log "save skipped: exact key $hash already stored"; exit 0; fi
    rel=()
    for p in "${paths[@]}"; do [ -e "$p" ] && rel+=("${p#/}"); done
    if [ ${#rel[@]} -eq 0 ]; then log "save skipped: nothing to store"; exit 0; fi
    if ! tar -I 'zstd -T0 -3' -cf "$tmp" -C / "${rel[@]}" 2>/dev/null; then echo "::warning::lang-cache $name: pack failed"; exit 0; fi
    size=$(du -m "$tmp" | cut -f1)
    exp=${LC_EXPIRES:-720h}
    if nsc artifact upload --expires_in "$exp" "$tmp" "$exact" >/dev/null 2>&1 &&
      nsc artifact upload --expires_in "$exp" "$tmp" "$latest" >/dev/null 2>&1; then
      log "save key=$hash ${size}MB in $(since "$t0")s"
    else
      echo "::warning::lang-cache $name: upload failed (cache stays as it was)"
    fi
    rm -f "$tmp"
    ;;
esac
exit 0
