# dpoc-sticky spike (C): Go module cache as a fixed-output derivation, so it lives in /nix/store
# (content-addressed, covered by the /nix volume and its GC). Update outputHash whenever go.sum changes.
{ pkgs, go }:
pkgs.stdenvNoCC.mkDerivation {
  name = "go-base-modcache";
  src = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [
      ../go.mod
      ../go.sum
    ];
  };
  nativeBuildInputs = [
    go
    pkgs.cacert
  ];
  dontConfigure = true;
  dontFixup = true;
  buildPhase = ''
    export HOME=$TMPDIR GOMODCACHE=$out GOTOOLCHAIN=local GOFLAGS=-mod=mod GOPROXY=https://proxy.golang.org,direct
    go mod download
    rm -rf $out/cache/download/sumdb $out/cache/vcs
  '';
  installPhase = "true";
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = "sha256-6Ug5adMFigGWCByQAyPIoKj8Ev6l8p1QMVw/s6+21YY=";
}
