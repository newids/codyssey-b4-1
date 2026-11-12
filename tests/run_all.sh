#!/usr/bin/env bash
# 모든 테스트 실행. 사용: tests/run_all.sh  (Linux/macOS 공통, root 불필요)
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
rc=0
for t in tests/test_*.sh; do
  echo "=== $t"
  bash "$t" || rc=1
  echo
done
(( rc == 0 )) && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $rc
