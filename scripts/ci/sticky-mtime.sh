#!/usr/bin/env bash
# sticky-mtime.sh before|after: make MSBuild incremental builds work on a sticky obj/ + bin/ after a fresh checkout.
# A fresh checkout stamps every source file "now", newer than the cached obj/ outputs, so MSBuild recompiles all.
# before: every tracked file whose content (git blob id) equals the manifest saved next to the cached outputs gets an
#         old fixed mtime (2001-01-01); changed or new files keep "now" and are rebuilt. No manifest = cold, no change.
# after:  prints which assemblies were compiled in this job (COMPILED yes/no), then saves the manifest (success only).
set -uo pipefail
dir="${STICKY_DOTNET_DIR:-$HOME/.sticky-dotnet}"
manifest="$dir/manifest"
stamp="${RUNNER_TEMP:-/tmp}/sticky-build-start"
mkdir -p "$dir"
case ${1:?} in
before)
  touch "$stamp"
  if [ ! -s "$manifest" ]; then
    echo "MTIME no-manifest (cold obj/bin)"
    exit 0
  fi
  t0=$(date +%s.%N)
  # unchanged = same "mode blob path" line in both lists
  git -c core.quotepath=off ls-files -s | sed 's/ [0-3]\t/ /' | sort >"$stamp.now"
  comm -12 "$stamp.now" <(sort "$manifest") | cut -d" " -f3- >"$stamp.same"
  same=$(wc -l <"$stamp.same")
  changed=$(($(wc -l <"$stamp.now") - same))
  tr '\n' '\0' <"$stamp.same" | xargs -0 -r touch -h -d @978307200
  echo "MTIME unchanged=$same changed=$changed took=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.2f", b-a}')s"
  ;;
after)
  for f in */obj/*/net*/*.dll; do
    [ -f "$f" ] || continue
    if [ "$f" -nt "$stamp" ]; then echo "COMPILED yes $f"; else echo "COMPILED no $f"; fi
  done
  ;;
save)
  git -c core.quotepath=off ls-files -s | sed 's/ [0-3]\t/ /' >"$manifest.tmp" && mv "$manifest.tmp" "$manifest"
  echo "MTIME manifest saved ($(wc -l <"$manifest") files)"
  ;;
esac
exit 0
