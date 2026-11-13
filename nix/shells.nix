{
  pkgs,
  packages,
  env,
  shellHook,
  preCommitConfig,
}:
with env;
{
  # CI shells install no git hooks: nothing commits in CI. The Pre-Commit job links
  # the generated config itself (scripts/ci/pre-commit.sh reads PRE_COMMIT_CONFIG_FILE).
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    PRE_COMMIT_CONFIG_FILE = preCommitConfig;
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
