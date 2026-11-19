#!/usr/bin/env bash
# 제공 앱 두 버전(인텔/실리콘) 중 이 호스트 아키텍처에 맞는 것만 $AGENT_HOME 에 배치한다.
#   사용: sudo scripts/setup/install-app.sh [바이너리가 들어 있는 디렉토리]
#   기본 원본 디렉토리: 저장소의 agent-app/ (agent-app.zip 을 푼 곳)
#   root 로 실행하면 소유자 agent-admin, 그룹 agent-core, 권한 750 으로 설치한다.
#   (소유자/그룹은 APP_OWNER / APP_GROUP 로 바꿀 수 있다)
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/app-arch.sh"

SRC_DIR="${1:-${REPO_ROOT}/agent-app}"
ARCH="$(detect_host_arch)"
BIN="$(resolve_app_binary "$ARCH")" || exit 1
SRC="${SRC_DIR}/${BIN}"

[[ -f "$SRC" ]] || die "앱 파일이 없다: $SRC  (agent-app.zip 을 ${SRC_DIR} 에 풀었는지 확인)"
[[ -d "$AGENT_HOME" ]] || die "$AGENT_HOME 이 없다 (02-users-groups-dirs.sh 먼저 실행)"

APP_OWNER="${APP_OWNER:-agent-admin}"
APP_GROUP="${APP_GROUP:-$GROUP_CORE}"
OWNER_OPTS=()
if [[ "$(id -u)" -eq 0 ]]; then
  id "$APP_OWNER" >/dev/null 2>&1 || die "${APP_OWNER} 계정이 없다 (02-users-groups-dirs.sh 먼저 실행)"
  OWNER_OPTS=(-o "$APP_OWNER" -g "$APP_GROUP")
fi

install ${OWNER_OPTS[@]+"${OWNER_OPTS[@]}"} -m 750 "$SRC" "${AGENT_HOME}/${BIN}" || die "설치 실패: ${AGENT_HOME}/${BIN}"
info "호스트 아키텍처: ${ARCH} → ${BIN}"
info "installed: ${AGENT_HOME}/${BIN}"
