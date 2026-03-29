#!/usr/bin/env bats

load test_helper/common

setup() {
  load_nixdash
  setup_test_config
}

teardown() {
  teardown_test_config
}

@test "config_get returns empty for missing key" {
  run config_get "packages_file"
  assert_success
  assert_output ""
}

@test "config_set writes key to file" {
  config_set "packages_file" "/home/user/packages.nix"
  run cat "$CONFIG_FILE"
  assert_output --partial 'packages_file = "/home/user/packages.nix"'
}

@test "config_get reads key from file" {
  config_set "packages_file" "/home/user/packages.nix"
  run config_get "packages_file"
  assert_success
  assert_output "/home/user/packages.nix"
}

@test "config_set updates existing key" {
  config_set "packages_file" "/old/path.nix"
  config_set "packages_file" "/new/path.nix"
  run config_get "packages_file"
  assert_success
  assert_output "/new/path.nix"
}

@test "config_set handles multiple keys" {
  config_set "packages_file" "/home/user/packages.nix"
  config_set "apply_command" "home-manager switch"
  config_set "auto_apply" "false"
  run config_get "packages_file"
  assert_output "/home/user/packages.nix"
  run config_get "apply_command"
  assert_output "home-manager switch"
  run config_get "auto_apply"
  assert_output "false"
}

@test "config_set handles section keys" {
  config_set "flake.inputs_line" "4"
  run config_get "flake.inputs_line"
  assert_success
  assert_output "4"
}

@test "config_is_initialized returns false when no config" {
  run config_is_initialized
  assert_failure
}

@test "config_is_initialized returns true when packages_file set" {
  config_set "packages_file" "/some/path.nix"
  config_set "apply_command" "hms"
  run config_is_initialized
  assert_success
}
