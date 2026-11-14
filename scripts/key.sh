#!/usr/bin/env bash
# usage: key.sh <lang> -> hash of that language's lock inputs
cd "$(dirname "$0")/.." || exit 1
case $1 in
  bun) f=(bun/bun.lock) ;;
  go) f=(go/go.sum) ;;
  dotnet) mapfile -t f < <(find dotnet -name 'Directory.Packages.props' -o -name '*.csproj' | sort) ;;
  dart) mapfile -t f < <(find dart -name pubspec.yaml | sort) ;;
esac
cat "${f[@]}" | sha256sum | cut -c1-16
