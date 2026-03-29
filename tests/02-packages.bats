#!/usr/bin/env bats

load test_helper/common

setup() {
  load_nixdash
  setup_test_config
  TEST_PKG_FILE="$(create_test_packages_file)"
  config_set "packages_file" "$TEST_PKG_FILE"
  # Also need a flake file for flake prefix detection
  TEST_FLAKE_FILE="$(create_test_flake_file)"
  config_set "flake_file" "$TEST_FLAKE_FILE"
}

teardown() {
  teardown_test_config
  rm -f "$TEST_PKG_FILE" "$TEST_FLAKE_FILE"
}

@test "packages_list extracts all packages" {
  run packages_list
  assert_success
  assert_line "bat"
  assert_line "ripgrep"
  assert_line "fzf"
}

@test "packages_list includes prefixed packages" {
  run packages_list
  assert_success
  assert_line "nodePackages.typescript"
}

@test "packages_list includes flake inputs" {
  run packages_list
  assert_success
  # Check for wt and zigpkgs entries
  assert_output --partial "wt.packages"
  assert_output --partial "zigpkgs.master"
}

@test "packages_list includes conditional packages" {
  run packages_list
  assert_success
  assert_line "papirus-icon-theme"
  assert_line "bibata-cursors"
}

@test "packages_type returns nixpkgs for simple packages" {
  run packages_type "bat"
  assert_success
  assert_output "nixpkgs"
}

@test "packages_type returns flake for flake inputs" {
  run packages_type 'wt.packages.${system}.default'
  assert_success
  assert_output "flake"
}

@test "packages_type returns nixpkgs for prefixed packages" {
  run packages_type "nodePackages.typescript"
  assert_success
  assert_output "nixpkgs"
}

@test "packages_condition returns linux for conditional packages" {
  run packages_condition "papirus-icon-theme"
  assert_success
  assert_output "linux"
}

@test "packages_condition returns empty for main list packages" {
  run packages_condition "bat"
  assert_success
  assert_output ""
}

@test "packages_is_installed returns 0 for installed package" {
  run packages_is_installed "bat"
  assert_success
}

@test "packages_is_installed returns 1 for missing package" {
  run packages_is_installed "curl"
  assert_failure
}

@test "packages_add inserts package into main list" {
  packages_add "curl"
  run packages_is_installed "curl"
  assert_success
  run grep "curl" "$TEST_PKG_FILE"
  assert_success
}

@test "packages_remove deletes package from file" {
  packages_remove "bat"
  run packages_is_installed "bat"
  assert_failure
  run packages_is_installed "ripgrep"
  assert_success
}

@test "packages_display_name returns short name for flake" {
  run packages_display_name 'wt.packages.${system}.default'
  assert_success
  assert_output "wt"
}

@test "packages_display_name returns name as-is for nixpkgs" {
  run packages_display_name "ripgrep"
  assert_success
  assert_output "ripgrep"
}
