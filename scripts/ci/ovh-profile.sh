#!/usr/bin/env bash
# dpoc-ovh spike only: where do the seconds of `nix develop` / durian-shell go on this runner?
# usage: ovh-profile.sh <devshell-name>
set -uo pipefail
sh="$1"
T="${RUNNER_TEMP:-/tmp}/ovh"
mkdir -p "$T"
d() { awk -v a="$1" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.3f", b-a}'; }
prof() { # <trace file> <label>: top functions and lines by wall time
  awk -v L="$2" '
    /^\++[0-9]+\.[0-9]+ / { line=$0; sub(/^\++/,"",line); split(line,a," "); ts=a[1]; fn=a[2];
      cmd=substr(line, length(a[1])+length(a[2])+3, 110);
      if (pts!="") { dt=ts-pts; F[pfn]+=dt; C[pcmd]+=dt; N[pcmd]++ } pts=ts; pfn=fn; pcmd=cmd }
    END { for (f in F) printf "OVHP %s F %.3f %s\n", L, F[f], f; for (c in C) printf "OVHP %s L %.3f n=%d %s\n", L, C[c], N[c], c }' "$1" |
    sort -k4 -rn | awk '$3=="F"' | head -12
  awk -v L="$2" '
    /^\++[0-9]+\.[0-9]+ / { line=$0; sub(/^\++/,"",line); split(line,a," "); ts=a[1]; fn=a[2];
      cmd=substr(line, length(a[1])+length(a[2])+3, 110);
      if (pts!="") { dt=ts-pts; C[pcmd]+=dt; N[pcmd]++ } pts=ts; pcmd=cmd }
    END { for (c in C) printf "OVHP %s L %.3f n=%d %s\n", L, C[c], N[c], c }' "$1" | sort -k4 -rn | head -25
}
echo "OVH bash=$BASH_VERSION os=$(uname -sm) cpus=$(getconf _NPROCESSORS_ONLN)"
t=$EPOCHREALTIME; nix develop ".#$sh" -c true; echo "OVH develop-again $(d "$t")"
for i in 1 2 3; do t=$EPOCHREALTIME; nix --version >/dev/null; echo "OVH nix-version $(d "$t")"; done
t=$EPOCHREALTIME; nix config show system >/dev/null; echo "OVH nix-config-show $(d "$t")"
t=$EPOCHREALTIME; nix print-dev-env ".#$sh" >"$T/env.sh"; echo "OVH print-dev-env $(d "$t") bytes=$(wc -c <"$T/env.sh")"
for i in 1 2 3; do t=$EPOCHREALTIME; bash --norc --noprofile -c 'true'; echo "OVH bash-bare $(d "$t")"; done
for i in 1 2; do t=$EPOCHREALTIME; bash --norc --noprofile -c "source $T/env.sh >/dev/null 2>&1; true"; echo "OVH env-source $(d "$t")"; done
PS4='+${EPOCHREALTIME} ${FUNCNAME[0]:-main} ' bash --norc --noprofile -x -c "source $T/env.sh" 2>"$T/env.trace" >/dev/null
echo "OVH env-trace-lines $(wc -l <"$T/env.trace")"
prof "$T/env.trace" env
# durian-shell (GNU find/sed from the dev shell itself; macOS has BSD ones)
tools="$(nix develop ".#$sh" -c bash -c 'for t in find sed sha256sum; do dirname "$(command -v $t)"; done' | sort -u | tr '\n' ':')"
export DURIAN_SHELL_CACHE=1 DURIAN_SHELL_DIR=/nix/durian-shell DURIAN_SHELL_SCOPE="ovh-$GITHUB_REPOSITORY"
ds="$(command -v durian-shell)"
t=$EPOCHREALTIME; PATH="$tools$PATH" "$ds" ".#$sh" -c true; echo "OVH durian-1st rc=$? $(d "$t")"
for i in 1 2 3; do t=$EPOCHREALTIME; PATH="$tools$PATH" "$ds" ".#$sh" -c true; echo "OVH durian-hit rc=$? $(d "$t")"; done
PATH="$tools$PATH" PS4='+${EPOCHREALTIME} ${FUNCNAME[0]:-main} ' bash -x "$ds" ".#$sh" -c true 2>"$T/ds.trace"
echo "OVH ds-trace-lines $(wc -l <"$T/ds.trace")"
prof "$T/ds.trace" durian
# the env script exactly as the hit runs it (bash from the cached env)
envf="$(ls -t /nix/durian-shell/*/*.sh 2>/dev/null | head -1)"
bb="$(sed -n 's/^# durian-bash: //p' "$envf" | head -1)"
for i in 1 2; do t=$EPOCHREALTIME; "$bb" --norc --noprofile -c "source $envf >/dev/null 2>&1; true"; echo "OVH cached-env-under-nix-bash $(d "$t")"; done
for i in 1 2; do t=$EPOCHREALTIME; "$bb" --norc --noprofile -c true; echo "OVH nix-bash-bare $(d "$t")"; done
exit 0
