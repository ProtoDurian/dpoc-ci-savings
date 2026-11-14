#!/usr/bin/env bash
# probe.sh before|after  (sticky-disk spike: dpoc-sticky-*)
#   before: SEEN markers (which earlier jobs' writes reached this volume copy), sizes, df
#   after:  writes this job's marker, prunes over-cap folders (writer branch only), sizes, df
#   STICKY_PATHS (newline list), STICKY_CAPS ("path:MB" lines), STICKY_JOB, STICKY_WRITE_BRANCH, STICKY_MAX_PCT (default 70)
set -uo pipefail
m="$HOME/.sticky-markers"
mkdir -p "$m"
exp() {
  local p="${1/#\~/$HOME}"
  [[ $p != /* ]] && p="${GITHUB_WORKSPACE:-$PWD}/$p"
  echo "$p"
}
sizes() {
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    q=$(exp "$p")
    echo "SIZE-$1 $(du -sm "$q" 2>/dev/null | cut -f1 || echo 0)MB $(find "$q" -xdev 2>/dev/null | wc -l)files $p"
  done <<<"${STICKY_PATHS:-}"
  echo "DF-$1 $(df -m /cache 2>/dev/null | awk 'NR==2{print $3"MB used of "$2"MB ("$5")"}')"
}
case ${1:?} in
before)
  echo "SEEN $(find "$m" -mindepth 1 -printf "%f\n" | sort | tr "\n" " ")"
  echo "SEEN-COUNT $(find "$m" -mindepth 1 | wc -l)"
  sizes before
  ;;
after)
  touch "$m/${STICKY_JOB:-job}--${GITHUB_RUN_NUMBER:-0}--${GITHUB_REF_NAME:-local}"
  if [ "${GITHUB_REF_NAME:-}" = "${STICKY_WRITE_BRANCH:-main}" ]; then
    # rule 1: per-folder caps
    while IFS= read -r c; do
      [ -z "$c" ] && continue
      p=$(exp "${c%:*}")
      cap=${c##*:}
      s=$(du -sm "$p" 2>/dev/null | cut -f1 || echo 0)
      if [ "${s:-0}" -gt "$cap" ]; then
        find "$p" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
        echo "PRUNED $p was ${s}MB > cap ${cap}MB"
      fi
    done <<<"${STICKY_CAPS:-}"
    # rule 2: whole volume guard: lang caches go first, before Nix store GC would
    pct=$(df /cache 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}')
    if [ "${pct:-0}" -ge "${STICKY_MAX_PCT:-70}" ]; then
      while IFS= read -r p; do [ -n "$p" ] && find "$(exp "$p")" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; done <<<"${STICKY_PATHS:-}"
      echo "PRUNED-ALL volume at ${pct}% >= ${STICKY_MAX_PCT:-70}%"
    fi
  fi
  sizes after
  ;;
esac
exit 0
