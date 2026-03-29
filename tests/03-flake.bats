#!/usr/bin/env bats

load test_helper/common

setup() {
  load_nixdash
  setup_test_config
  TEST_FLAKE_FILE="$(create_test_flake_file)"
  TEST_PKG_FILE="$(create_test_packages_file)"
  config_set "flake_file" "$TEST_FLAKE_FILE"
  config_set "packages_file" "$TEST_PKG_FILE"
}

teardown() {
  teardown_test_config
  rm -f "$TEST_FLAKE_FILE" "$TEST_PKG_FILE"
}

@test "flake_list_inputs extracts input names" {
  run flake_list_inputs
  assert_success
  assert_line "nixpkgs"
  assert_line "home-manager"
  assert_line "wt"
}

@test "flake_get_input_url returns URL for input" {
  run flake_get_input_url "wt"
  assert_success
  assert_output "github:AThevon/wt"
}

@test "flake_get_input_url returns empty for unknown input" {
  run flake_get_input_url "nonexistent"
  assert_success
  assert_output ""
}

@test "flake_find_inputs_end returns correct line" {
  run flake_find_inputs_end
  assert_success
  [[ "$output" -gt 0 ]]
}

@test "flake_find_extra_special_args returns correct line" {
  run flake_find_extra_special_args
  assert_success
  [[ "$output" -gt 0 ]]
}

@test "flake_add_input adds input to flake.nix" {
  flake_add_input "newtool" "github:someone/newtool"
  # Block style: newtool = { url = "..."; };
  run grep 'url = "github:someone/newtool"' "$TEST_FLAKE_FILE"
  assert_success
  run grep "inputs.nixpkgs.follows" "$TEST_FLAKE_FILE"
  assert_success
}

@test "flake_add_inherit adds inherit to extraSpecialArgs" {
  flake_add_inherit "newtool"
  run grep "inherit.*newtool" "$TEST_FLAKE_FILE"
  assert_success
}

@test "flake_remove_input removes input and inherit" {
  flake_remove_input "wt"
  run grep "wt.url" "$TEST_FLAKE_FILE"
  assert_failure
  run grep "wt.inputs.nixpkgs.follows" "$TEST_FLAKE_FILE"
  assert_failure
  run grep "inherit wt" "$TEST_FLAKE_FILE"
  assert_failure
}
