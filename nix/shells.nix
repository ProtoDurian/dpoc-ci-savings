{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
{
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
    inherit shellHook;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    inherit shellHook;
  };

  # dpoc-ovh: the ci shell without the git-hooks shellHook (pre-commit install ~1.5 s per job).
  # Only the Pre-Commit job needs the hooks; test/build jobs never commit.
  ci-nohook = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
  };

  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    inherit shellHook;
  };

  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
