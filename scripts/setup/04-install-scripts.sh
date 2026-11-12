#!/usr/bin/env bash
# 요구사항 4: monitor.sh(+ 보너스 report.sh, log_retention.sh) 를 $AGENT_HOME/bin 에 배치
#   소유자 agent-dev, 그룹 agent-core, 권한 750
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"
require_root

BIN_DIR="${AGENT_HOME}/bin"
[[ -d "$BIN_DIR" ]] || die "$BIN_DIR 이 없다 (02-users-groups-dirs.sh 먼저 실행)"

for s in monitor.sh report.sh log_retention.sh; do
  install -o agent-dev -g "$GROUP_CORE" -m 750 "${REPO_ROOT}/scripts/${s}" "${BIN_DIR}/${s}"
  info "installed: ${BIN_DIR}/${s}"
done
bash -n "${BIN_DIR}/monitor.sh" && info "monitor.sh 문법 검사 OK"
ls -l "$BIN_DIR"

echo
info "agent-admin 으로 실행 가능 여부 확인 (앱이 떠 있지 않으면 exit 1 이 정상):"
su - agent-admin -c ". ${ENV_FILE}; ${BIN_DIR}/monitor.sh; echo \"exit=\$?\"" || true
