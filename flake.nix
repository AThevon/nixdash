{
  description = "nixdash - TUI for managing Nix packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages = {
          nixdash = pkgs.callPackage ./default.nix {};
          default = self.packages.${system}.nixdash;
        };
      }
    ) // {
      overlays.default = final: prev: {
        nixdash = final.callPackage ./default.nix {};
      };
    };
}
