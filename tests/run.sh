#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

test_files=()
while IFS= read -r f; do
  test_files+=("$f")
done < <(find "$TESTS_DIR" -maxdepth 1 -name "*.bats" | sort)

if [[ ${#test_files[@]} -eq 0 ]]; then
  echo "No test files found" >&2
  exit 1
fi

"$TESTS_DIR/bats/bin/bats" "${test_files[@]}"
