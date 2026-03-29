#!/usr/bin/env bats

load test_helper/common

@test "nixdash.sh prints version" {
  run bash "$NIXDASH_ROOT/nixdash.sh" --version
  assert_success
  assert_output --partial "nixdash"
}

@test "nixdash.sh shows help" {
  run bash "$NIXDASH_ROOT/nixdash.sh" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "nixdash.sh rejects unknown command" {
  run bash "$NIXDASH_ROOT/nixdash.sh" foobar
  assert_failure
  assert_output --partial "unknown command"
}
