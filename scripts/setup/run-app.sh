#!/usr/bin/env bash
# 제공 앱 실행 도우미: 호스트 아키텍처에 맞는 버전을 골라 실행 (일반 계정 agent-admin 으로 실행, root 금지)
#   사용: su - agent-admin  →  bash /path/to/run-app.sh
#   AGENT_USE_MOCK=1 이면 저장소의 scripts/mock/agent_app.py(테스트 대역)를 대신 실행한다
set -u
ENV_FILE="${AGENT_ENV_FILE:-/etc/profile.d/agent-env.sh}"
# shellcheck source=/dev/null
[[ -f "$ENV_FILE" ]] && . "$ENV_FILE"
: "${AGENT_HOME:?AGENT_HOME 미설정 (03-env-keyfile.sh 실행 여부 확인)}"

[[ "$(id -u)" -ne 0 ]] || { echo "[ERROR] root 로 실행 금지. su - agent-admin 후 실행" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ "${AGENT_USE_MOCK:-0}" == "1" ]]; then
  echo "[INFO] mock 앱 실행 (제출용 아님)"; exec python3 "${REPO_ROOT}/scripts/mock/agent_app.py"
fi

# 호스트 아키텍처를 확인해 인텔(x86)/실리콘(arm64) 버전 중 맞는 것을 고른다
# shellcheck source=app-arch.sh
source "$(dirname "${BASH_SOURCE[0]}")/app-arch.sh"
ARCH="$(detect_host_arch)"
BIN="$(resolve_app_binary "$ARCH")" || exit 1
APP="${AGENT_HOME}/${BIN}"
[[ -f "$APP" ]] || { echo "[ERROR] ${ARCH} 용 앱 파일이 없다: $APP  (sudo scripts/setup/install-app.sh 로 배치)" >&2; exit 1; }
[[ -x "$APP" ]] || chmod u+x "$APP"
echo "[INFO] 호스트 아키텍처: ${ARCH} → ${BIN}"
echo "[INFO] 실행: $APP (종료는 Ctrl+C)"
exec "$APP"
