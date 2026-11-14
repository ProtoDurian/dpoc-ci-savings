#!/usr/bin/env bash
# bench.sh <phase>: restore-speed micro-benchmark for the real Gradle cache (sticky spike, Flutter part (E)).
#   pack:    copy the real ~/.gradle/{caches,wrapper} off the sticky volume to $SRC, build every archive/image, upload
#   restore: for every method: drop page cache, download, unpack/mount; print BENCH lines
#   build:   mount the erofs/squashfs image (+ overlay upper) at ~/.gradle and run the real Gradle build (separate step)
#   bin:     -all vs -bin Gradle distribution: size + unzip seconds
# Artifacts: dpoc-sticky-bench/fl/<method>, expire 24h, expired again at the end (cleanup phase).
set -uo pipefail
phase=${1:?}
W=${RUNNER_TEMP:-/tmp}/bench
SRC=$W/src            # holds home/runner/.gradle/{caches,wrapper} (relative to /)
A=$W/arch
P=dpoc-sticky-bench/fl
mkdir -p "$W" "$A"
now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN{printf "%.2f", b-a}'; }
drop() { sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; }
mb() { du -sm "$1" 2>/dev/null | cut -f1; }
rel=home/runner/.gradle
methods="zst1 zst3 tar lz4 split4 sqfs erofs"

pack_one() { # method -> $A/<file>
  local m=$1 t0
  t0=$(now)
  case $m in
  zst1) tar -C "$SRC" -cf - "$rel" | zstd -q -T0 -1 -o "$A/zst1.tzst" ;;
  zst3) tar -C "$SRC" -cf - "$rel" | zstd -q -T0 -3 -o "$A/zst3.tzst" ;;
  zst19) tar -C "$SRC" -cf - "$rel" | timeout 1200 zstd -q -T0 -19 -o "$A/zst19.tzst" || { echo "BENCH zst19 pack TIMEOUT"; rm -f "$A/zst19.tzst"; } ;;
  tar) tar -C "$SRC" -cf "$A/tar.tar" "$rel" ;;
  lz4) tar -C "$SRC" -cf - "$rel" | lz4 -q -1 - "$A/lz4.tlz4" ;;
  split4)
    # 4 parts, each its own zstd -1 archive, restored in parallel (download + unpack per part)
    (cd "$SRC/$rel" && ls -d caches/* wrapper) >"$W/parts.all"
    rm -f "$W"/s[0-3]; : >"$W/p0"; : >"$W/p1"; : >"$W/p2"; : >"$W/p3"
    # greedy split by size, largest first
    while read -r s d; do
      i=0; best=0
      for k in 0 1 2 3; do v=$(cat "$W/s$k" 2>/dev/null || echo 0); if [ "$k" = 0 ] || [ "$v" -lt "$best" ]; then best=$v; i=$k; fi; done
      echo "$rel/$d" >>"$W/p$i"; echo $((best + s)) >"$W/s$i"
    done < <(cd "$SRC/$rel" && du -sm $(cat "$W/parts.all") | sort -rn)
    for k in 0 1 2 3; do echo "BENCH split4 part$k $(cat "$W/s$k" 2>/dev/null)MB: $(tr '\n' ' ' <"$W/p$k")"; done
    for k in 0 1 2 3; do (tar -C "$SRC" -cf - -T "$W/p$k" | zstd -q -T1 -1 -o "$A/split4.$k.tzst") & done
    wait
    ;;
  sqfs) mksquashfs "$SRC/$rel" "$A/sqfs.img" -comp lz4 -Xhc -processors 4 -no-progress -quiet >/dev/null ;;
  erofs) mkfs.erofs -zlz4hc "$A/erofs.img" "$SRC/$rel" >/dev/null 2>&1 || mkfs.erofs "$A/erofs.img" "$SRC/$rel" >/dev/null ;;
  esac
  echo "BENCH $m pack $(since "$t0")s size=$(du -cm "$A/$m".* 2>/dev/null | tail -1 | cut -f1)MB"
}

upload_one() {
  local m=$1 t0 f
  t0=$(now)
  for f in "$A/$m".*; do nsc artifact upload --expires_in 24h "$f" "$P/$(basename "$f")" >/dev/null 2>&1 || echo "BENCH $m upload FAILED $f"; done
  echo "BENCH $m upload $(since "$t0")s"
  rm -f "$A/$m".*
}

restore_one() { # prints download + unpack/mount seconds
  local m=$1 d=$W/r-$m t0 t1 dl un tot=
  sudo rm -rf "$d"; mkdir -p "$d"
  drop
  t0=$(now)
  case $m in
  zst1 | zst3 | zst19 | tar | lz4)

    ext=$(case $m in tar) echo tar ;; lz4) echo tlz4 ;; *) echo tzst ;; esac)
    nsc artifact download "$P/$m.$ext" "$A/$m.$ext" >/dev/null 2>&1 || { echo "BENCH $m download FAILED"; return; }
    dl=$(since "$t0"); t1=$(now)
    case $m in
    tar) tar -C "$d" -xf "$A/$m.$ext" ;;
    lz4) lz4 -dc "$A/$m.$ext" | tar -C "$d" -xf - ;;
    *) tar -C "$d" -I 'zstd -d -T0' -xf "$A/$m.$ext" ;;
    esac
    un=$(since "$t1"); tot=$(since "$t0")
    ;;
  split4)
    for k in 0 1 2 3; do (nsc artifact download "$P/split4.$k.tzst" "$A/split4.$k.tzst" >/dev/null 2>&1 && tar -C "$d" -I zstd -xf "$A/split4.$k.tzst") & done
    wait
    dl=0; un=$(since "$t0")
    ;;
  sqfs | erofs)
    nsc artifact download "$P/$m.img" "$A/$m.img" >/dev/null 2>&1 || { echo "BENCH $m download FAILED"; return; }
    dl=$(since "$t0"); t1=$(now)
    mkdir -p "$d/lower" "$d/upper" "$d/work" "$d/merged"
    if [ $m = sqfs ]; then sudo mount -t squashfs -o loop,ro "$A/$m.img" "$d/lower"; else sudo mount -t erofs -o loop,ro "$A/$m.img" "$d/lower"; fi || { echo "BENCH $m mount FAILED"; return; }
    sudo mount -t overlay overlay -o "lowerdir=$d/lower,upperdir=$d/upper,workdir=$d/work" "$d/merged" || { echo "BENCH $m overlay FAILED"; return; }
    un=$(since "$t1"); tot=$(since "$t0")
    # first full read of every file through the mount (what a cold Gradle start would pay at worst)
    t1=$(now); find "$d/merged" -type f -print0 | xargs -0 -P4 -n200 cat >/dev/null 2>&1
    echo "BENCH $m fullread $(since "$t1")s files=$(find "$d/merged" -type f | wc -l)"
    ;;
  esac
  echo "BENCH $m restore download=${dl}s unpack_or_mount=${un}s total=${tot:-$(since "$t0")}s restored=$(mb "$d")MB"
  case $m in sqfs | erofs) ;; *) rm -f "$A/$m".*; sudo rm -rf "$d" ;; esac
}

stream_one() { # download piped straight into tar (no temp file)
  local m=$1 d=$W/s-$m t0
  sudo rm -rf "$d"; mkdir -p "$d"; drop; t0=$(now)
  if nsc artifact download "$P/$m.tzst" /dev/stdout 2>/dev/null | tar -C "$d" -I 'zstd -d' -xf - 2>/dev/null && [ "$(mb "$d")" -gt 100 ]; then
    echo "BENCH stream-$m stdout total=${tot:-$(since "$t0")}s restored=$(mb "$d")MB"
  else
    echo "BENCH stream-$m stdout FAILED ($(mb "$d")MB)"
    sudo rm -rf "$d"; mkdir -p "$d"; drop; t0=$(now)
    mkfifo "$W/fifo"
    (nsc artifact download "$P/$m.tzst" "$W/fifo" >/dev/null 2>&1; echo "dl rc=$?" >"$W/fifo.rc") &
    tar -C "$d" -I 'zstd -d' -xf "$W/fifo" 2>/dev/null
    wait
    echo "BENCH stream-$m fifo total=$(since "$t0")s restored=$(mb "$d")MB $(cat "$W/fifo.rc" 2>/dev/null)"
    rm -f "$W/fifo"
  fi
  sudo rm -rf "$d"
}

case $phase in
pack)
  t0=$(now)
  for x in zstd lz4 mksquashfs mkfs.erofs; do echo "TOOL $x $(command -v $x || echo MISSING)"; done
  echo "FS home: $(df -T "$HOME" | awk 'NR==2{print $2, $3/1024/1024 "GiB used of", $2}') cache: $(df -T /cache 2>/dev/null | awk 'NR==2{print $2}') tmp: $(df -T "$W" | awk 'NR==2{print $2, $5/1024/1024 "GiB free"}')"
  g=$(du -sm "$HOME/.gradle/caches" | cut -f1); [ "${g:-0}" -ge 1000 ] || { echo "BENCH-ABORT empty volume (gradle caches ${g}MB, df $(df -m /cache | awk 'NR==2{print $3}')MB): no real cache to bench"; exit 1; }
  mkdir -p "$SRC/$rel"
  # the real cache from the sticky volume (bind mounts at ~/.gradle/caches and ~/.gradle/wrapper)
  cp -a "$HOME/.gradle/caches" "$HOME/.gradle/wrapper" "$SRC/$rel/"
  echo "BENCH copy-off-volume $(since "$t0")s src=$(mb "$SRC")MB files=$(find "$SRC" -type f | wc -l)"
  for d in "$SRC/$rel"/caches/* "$SRC/$rel/wrapper"; do echo "PART $(mb "$d")MB $(find "$d" -type f | wc -l)files ${d#"$SRC/$rel/"}"; done
  # reflink check (same fs copy)
  t0=$(now); cp -a --reflink=always "$SRC/$rel/caches" "$W/reflink-test" 2>/dev/null && echo "BENCH reflink $(since "$t0")s" || echo "BENCH reflink unsupported on $(df -T "$W" | awk 'NR==2{print $2}')"; rm -rf "$W/reflink-test"
  t0=$(now); cp -a "$SRC/$rel/caches" "$W/plaincopy-test"; echo "BENCH plain-local-copy $(since "$t0")s"; rm -rf "$W/plaincopy-test"
  for m in $methods; do pack_one "$m"; upload_one "$m"; done
  ;;
restore)
  for m in $methods; do restore_one "$m"; done
  stream_one zst1
  stream_one zst3
  ;;
build)
  # swap the sticky bind mounts for the erofs image (+overlay upper) and build for real
  m=${2:-erofs}; mountpoint -q "$W/r-$m/merged" || m=sqfs
  d=$W/r-$m
  mountpoint -q "$d/merged" || restore_one "$m"
  sudo umount "$HOME/.gradle/caches" "$HOME/.gradle/wrapper" 2>/dev/null
  mountpoint -q "$HOME/.gradle/caches" && { echo "BENCH build: could not unmount sticky caches"; exit 0; }
  rm -rf "$HOME/.gradle/caches" "$HOME/.gradle/wrapper"
  ln -s "$d/merged/caches" "$HOME/.gradle/caches"
  ln -s "$d/merged/wrapper" "$HOME/.gradle/wrapper"
  ls -la "$HOME/.gradle"
  echo "BENCH build-on-$m ready"
  ;;
bin)
  for v in all bin; do
    t0=$(now); curl -fsSL -o "$W/g-$v.zip" "https://services.gradle.org/distributions/gradle-9.1.0-$v.zip"; dl=$(since "$t0")
    t0=$(now); mkdir -p "$W/g-$v"; unzip -q "$W/g-$v.zip" -d "$W/g-$v"
    echo "BENCH gradle-$v zip=$(mb "$W/g-$v.zip")MB unzipped=$(mb "$W/g-$v")MB files=$(find "$W/g-$v" -type f | wc -l) download=${dl}s unzip=$(since "$t0")s"
    rm -rf "$W/g-$v" "$W/g-$v.zip"
  done
  ;;
cleanup)
  for f in zst1.tzst zst3.tzst zst19.tzst tar.tar lz4.tlz4 split4.0.tzst split4.1.tzst split4.2.tzst split4.3.tzst sqfs.img erofs.img; do
    nsc artifact expire "$P/$f" >/dev/null 2>&1 && echo "EXPIRED $P/$f" || echo "EXPIRE-FAILED $P/$f"
  done
  ;;
esac
exit 0
