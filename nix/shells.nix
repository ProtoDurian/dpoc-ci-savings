{
  pkgs,
  packages,
  env,
  shellHook,
  gomod,
}:
with env;
let
  # dpoc-sticky spike (C): read-only module cache from /nix/store; GOPROXY=off proves nothing is fetched
  nixmod = {
    GOMODCACHE = "${gomod}";
    GOFLAGS = "-mod=mod";
    GOPROXY = "off";
  };
in
{
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
    inherit shellHook;
  };

  ci = pkgs.mkShell (
    nixmod
    // {
      buildInputs = lint ++ main ++ system;
      inherit shellHook;
    }
  );

  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    inherit shellHook;
  };

  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
