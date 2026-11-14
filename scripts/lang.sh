#!/usr/bin/env bash
# usage: lang.sh <bun|go|dotnet|dart> <none|vol|art|gha|gcp> <phase: restore|work|save|all>
# Prints "T <lang> <opt> <phase>=<seconds>" lines and cache sizes; never fails the job on cache errors.
set -uo pipefail
lang=$1 opt=$2 phase=${3:-all}
root=$(cd "$(dirname "$0")/.." && pwd)
key="${CACHE_KEY:-nokey}"

case $lang in
  bun) dirs=("$HOME/.bun/install/cache") ;;
  go) dirs=("$HOME/go/pkg/mod" "$HOME/.cache/go-build") ;;
  dotnet) dirs=("$HOME/.nuget/packages") ;;
  dart) dirs=("$HOME/.pub-cache") ;;
esac

now() { date +%s.%N; }
t() { awk -v a="$1" -v b="$(now)" 'BEGIN{printf "%.2f", b-a}'; }
size() { du -sm "${dirs[@]}" 2>/dev/null | awk '{s+=$1} END{print s+0}'; }

restore() {
  local s; s=$(now)
  case $opt in
    vol)
      local i=0
      for d in "${dirs[@]}"; do
        i=$((i + 1))
        src="/gitmirror/nscache/$lang/$i"
        sudo mkdir -p "$src" && sudo chown -R "$(id -u):$(id -g)" "/gitmirror/nscache/$lang"
        mkdir -p "$d"
        sudo mount --bind "$src" "$d"
      done
      echo "VOL-STATE $lang $( [ -n "$(ls -A "${dirs[0]}" 2>/dev/null)" ] && echo warm || echo empty) $(size)MB"
      ;;
    art)
      if nsc artifact download "nscache/$lang-$key.tar.zst" /tmp/c.tzst >/tmp/art-dl.log 2>&1; then
        echo "ART-HIT $(du -m /tmp/c.tzst | cut -f1)MB"
        tar -I zstd -xf /tmp/c.tzst -C / && touch /tmp/art-hit
      else
        echo "ART-MISS"; head -5 /tmp/art-dl.log
      fi
      ;;
  esac
  echo "T $lang $opt restore=$(t "$s")"
}

work() {
  local s; s=$(now)
  case $lang in
    bun) (cd "$root/bun" && bun install --frozen-lockfile) ;;
    go)
      if [ "$opt" = gcp ]; then
        export GOCACHEPROG="\"$HOME/.local/bin/gocacheprog\" -log-file /tmp/gcp.log"
      fi
      (cd "$root/go" && go mod download && timeout 240 go build ./... && timeout 240 go test -count=1 -run '^$' ./... >/dev/null) ;;
    dotnet) (cd "$root/dotnet" && dotnet restore dotnet-base.slnx -v q -p:NuGetAudit=false && dotnet build dotnet-base.slnx --no-restore -v q -nologo) ;;
    dart) (cd "$root/dart" && dart pub get) ;;
  esac
  local rc=$?
  [ -f /tmp/gcp.log ] && { echo "GCP-LOG:"; tail -25 /tmp/gcp.log; }
  echo "T $lang $opt work=$(t "$s") rc=$rc"
  echo "SIZE $lang $opt $(size)MB"
  return $rc
}

save() {
  local s; s=$(now)
  case $opt in
    art)
      if [ ! -e /tmp/art-hit ]; then
        tar -I 'zstd -T0 -3' -cf /tmp/c.tzst "${dirs[@]}" 2>/dev/null
        echo "ART-SIZE $(du -m /tmp/c.tzst | cut -f1)MB"
        nsc artifact upload --expires_in 48h /tmp/c.tzst "nscache/$lang-$key.tar.zst" 2>&1 | tail -2
      fi
      ;;
    vol)
      for d in "${dirs[@]}"; do sudo umount "$d" || true; done
      ;;
  esac
  echo "T $lang $opt save=$(t "$s")"
}

case $phase in
  restore) restore ;;
  work) work ;;
  save) save ;;
  all) restore; work; rc=$?; save; exit $rc ;;
esac
