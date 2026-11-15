{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in
    {
      devShells = forAll (pkgs: { default = pkgs.mkShell { packages = [ pkgs.hello pkgs.jq ]; }; ci = pkgs.mkShell { packages = [ pkgs.hello pkgs.jq ]; }; });
    };
}
