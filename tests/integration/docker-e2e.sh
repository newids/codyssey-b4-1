#!/usr/bin/env bash
# macOS/Linux 호스트에서 Ubuntu 22.04 컨테이너로 전체 흐름을 검증한다.
#   tests/integration/docker-e2e.sh
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
docker run --rm -v "$PWD:/repo:ro" ubuntu:22.04 bash /repo/tests/integration/inside-container.sh
