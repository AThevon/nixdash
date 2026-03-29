load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"

NIXDASH_ROOT="${BATS_TEST_DIRNAME}/.."

load_nixdash() {
  VERSION="test"
  source "$NIXDASH_ROOT/lib/config.sh"
  source "$NIXDASH_ROOT/lib/ui.sh"
  source "$NIXDASH_ROOT/lib/packages.sh"
  source "$NIXDASH_ROOT/lib/search.sh"
  source "$NIXDASH_ROOT/lib/shell.sh"
  source "$NIXDASH_ROOT/lib/flake.sh"
}

setup_test_config() {
  export CONFIG_DIR
  export CONFIG_FILE
  CONFIG_DIR="$(mktemp -d)"
  CONFIG_FILE="$CONFIG_DIR/config.toml"
}

teardown_test_config() {
  rm -rf "${CONFIG_DIR:-}"
}

create_test_packages_file() {
  local tmpfile
  tmpfile="$(mktemp --suffix=.nix)"
  cat > "$tmpfile" <<'NIXEOF'
{ pkgs, system, wt, zigpkgs, ... }:

{
  home.packages = with pkgs; [
    bat
    eza
    fd
    fzf
    ripgrep
    nodePackages.typescript
    wt.packages.${system}.default
    zigpkgs.master
  ] ++ lib.optionals stdenv.isLinux [
    papirus-icon-theme
    bibata-cursors
  ];
}
NIXEOF
  echo "$tmpfile"
}

create_test_flake_file() {
  local tmpfile
  tmpfile="$(mktemp --suffix=.nix)"
  cat > "$tmpfile" <<'NIXEOF'
{
  description = "Test dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    wt.url = "github:AThevon/wt";
    wt.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, wt, ... }:
    let
      mkHome = system: user: home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        extraSpecialArgs = {
          inherit wt;
        };
        modules = [ ./home ];
      };
    in {
      homeConfigurations = {
        "athevon@x86_64-linux" = mkHome "x86_64-linux" "athevon";
      };
    };
}
NIXEOF
  echo "$tmpfile"
}
