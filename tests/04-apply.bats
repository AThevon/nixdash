#!/usr/bin/env bats

load test_helper/common

setup() {
  load_nixdash
  setup_test_config
  export USER="alice"
  HM_CONFIGS=$'alice@aarch64-darwin\nalice@x86_64-linux'
  _apply_hm_configs() { echo "$HM_CONFIGS"; }
  _apply_current_system() { echo "aarch64-darwin"; }
  hostname() { echo "alice-laptop"; }
}

teardown() {
  teardown_test_config
}

@test "apply_resolve_command adds the configuration matching user@system" {
  run apply_resolve_command "home-manager switch --flake ~/.dotfiles"
  assert_success
  assert_output "home-manager switch --flake ~/.dotfiles#alice@aarch64-darwin"
}

@test "apply_resolve_command prefers user@hostname like home-manager" {
  HM_CONFIGS=$'alice@alice-laptop\nalice@aarch64-darwin'
  run apply_resolve_command "home-manager switch --flake /home/alice/cfg -b backup"
  assert_output "home-manager switch --flake /home/alice/cfg#alice@alice-laptop -b backup"
}

@test "apply_resolve_command uses the only configuration when nothing matches" {
  HM_CONFIGS="bob"
  run apply_resolve_command "home-manager switch --flake ."
  assert_output "home-manager switch --flake .#bob"
}

@test "apply_resolve_command leaves the command alone when unsure" {
  HM_CONFIGS=$'bob\ncarol'
  run apply_resolve_command "home-manager switch --flake ."
  assert_output "home-manager switch --flake ."
}

@test "apply_resolve_command keeps an explicit target" {
  run apply_resolve_command "home-manager switch --flake ~/.dotfiles#work"
  assert_output "home-manager switch --flake ~/.dotfiles#work"
}

@test "apply_resolve_command ignores other commands" {
  run apply_resolve_command "sudo nixos-rebuild switch --flake ."
  assert_output "sudo nixos-rebuild switch --flake ."
}

@test "apply_run saves the resolved command" {
  config_set "apply_command" "true home-manager switch --flake ."
  run apply_run
  assert_success
  run config_get "apply_command"
  assert_output "true home-manager switch --flake .#alice@aarch64-darwin"
}

@test "apply_run reports a failing apply command" {
  config_set "apply_command" "false"
  run apply_run
  assert_failure 1
  assert_output --partial "Apply failed (exit 1)"
}
