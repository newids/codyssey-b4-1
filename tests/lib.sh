#!/usr/bin/env bash
# 최소 테스트 하네스 (bats 없이 동작). 각 테스트 파일에서 source 한다.
set -u
PASS=0; FAIL=0
# shellcheck disable=SC2034  # 각 테스트 파일에서 사용
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/b41-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

_ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
_fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; [[ -n "${2:-}" ]] && echo "      $2"; }

assert_eq() {      # assert_eq <expected> <actual> <desc>
  if [[ "$1" == "$2" ]]; then _ok "$3"; else _fail "$3" "expected='$1' actual='$2'"; fi
}
assert_contains() { # assert_contains <haystack> <needle> <desc>
  if [[ "$1" == *"$2"* ]]; then _ok "$3"; else _fail "$3" "missing '$2' in: $(head -c 400 <<<"$1")"; fi
}
assert_not_contains() {
  if [[ "$1" != *"$2"* ]]; then _ok "$3"; else _fail "$3" "unexpected '$2'"; fi
}
assert_file_exists() { if [[ -e "$1" ]]; then _ok "$2"; else _fail "$2" "no file: $1"; fi }
assert_file_missing() { if [[ ! -e "$1" ]]; then _ok "$2"; else _fail "$2" "file exists: $1"; fi }

summary() {
  echo "----"
  echo "passed=$PASS failed=$FAIL"
  (( FAIL == 0 ))
}

# 테스트 케이스 간 격리: 새 작업 디렉토리를 만든다
new_case_dir() { local d; d="$(mktemp -d "$TMP_ROOT/case.XXXXXX")"; echo "$d"; }
