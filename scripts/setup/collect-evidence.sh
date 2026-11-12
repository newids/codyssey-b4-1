#!/usr/bin/env bash
# 수행 내역서용 증빙 자동 수집. root 로 실행하면 docs/evidence/*.txt 에 결과를 저장한다.
#   sudo scripts/setup/collect-evidence.sh [출력디렉토리]
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"
require_root
OUT="${1:-${REPO_ROOT}/docs/evidence}"
mkdir -p "$OUT"

capture() {  # capture <파일명> <설명> <명령...>
  local file="$OUT/$1" title="$2"; shift 2
  {
    echo "### $title"
    echo "\$ $*"
    echo
    bash -c "$*" 2>&1 || echo "(exit=$?)"
  } > "$file"
  info "saved: $file"
}

capture 01-sshd-config.txt     "SSH 포트/Root 로그인 설정"   "grep -nE '^(Port|PermitRootLogin)' /etc/ssh/sshd_config; echo '--- effective ---'; sshd -T 2>/dev/null | grep -Ei '^(port|permitrootlogin) '"
capture 02-sshd-listen.txt     "sshd 리슨 포트"               "ss -tulnp | grep -E 'sshd|:${SSH_PORT}\b'"
capture 03-firewall.txt        "방화벽 상태"                   "ufw status verbose 2>&1 || firewall-cmd --list-all 2>&1"
capture 04-users-groups.txt    "계정/그룹"                     "id agent-admin; id agent-dev; id agent-test; getent group ${GROUP_COMMON} ${GROUP_CORE}"
capture 05-directories.txt     "디렉토리 구조/권한"            "ls -ld /home/agent-admin ${AGENT_HOME} ${AGENT_UPLOAD_DIR} $(dirname ${AGENT_KEY_PATH}) ${AGENT_LOG_DIR} ${AGENT_HOME}/bin; echo; ls -la ${AGENT_HOME}"
capture 06-acl.txt             "ACL"                           "getfacl -p ${AGENT_UPLOAD_DIR} $(dirname ${AGENT_KEY_PATH}) ${AGENT_LOG_DIR}"
capture 07-permission-test.txt "권한 실동작 검증(test 는 core 자원 접근 불가)" "
  su - agent-test  -c 'touch ${AGENT_UPLOAD_DIR}/from-test.txt && ls -l ${AGENT_UPLOAD_DIR}/from-test.txt && rm ${AGENT_UPLOAD_DIR}/from-test.txt && echo \"[test] upload_files write OK\"';
  su - agent-test  -c 'cat ${AGENT_KEY_PATH} 2>&1 | head -1';
  su - agent-test  -c 'ls ${AGENT_LOG_DIR} 2>&1 | head -1';
  su - agent-dev   -c 'cat ${AGENT_KEY_PATH} && echo \"[dev] api_keys read OK\"';
  su - agent-admin -c 'touch ${AGENT_LOG_DIR}/.perm-test && rm ${AGENT_LOG_DIR}/.perm-test && echo \"[admin] log dir write OK\"'"
capture 08-env.txt             "환경 변수"                     "cat ${ENV_FILE}; echo '--- agent-admin shell ---'; su - agent-admin -c 'env | grep ^AGENT_ | sort'"
capture 09-keyfile.txt         "키 파일"                       "ls -l ${AGENT_KEY_PATH}; cat ${AGENT_KEY_PATH}; wc -l ${AGENT_KEY_PATH}"
capture 10-app-listen.txt      "앱 LISTEN 상태 (앱 실행 중이어야 함)" "ss -tlnp | grep ':${AGENT_PORT}\b' || echo 'NOT LISTENING - 앱을 먼저 실행하라'"
capture 11-monitor-script.txt  "monitor.sh 위치/소유/권한"     "ls -l ${AGENT_HOME}/bin/; stat -c '%U:%G %a %n' ${AGENT_HOME}/bin/monitor.sh"
capture 12-monitor-run.txt     "monitor.sh 실행 결과 (agent-admin)" "su - agent-admin -c '. ${ENV_FILE}; ${AGENT_HOME}/bin/monitor.sh; echo exit=\$?'"
capture 13-monitor-log.txt     "monitor.log 최근 기록"          "ls -l ${AGENT_LOG_DIR}; echo; tail -n 10 ${AGENT_LOG_DIR}/monitor.log"
capture 14-crontab.txt         "crontab 등록"                   "crontab -l -u agent-admin; echo; (grep CRON /var/log/syslog 2>/dev/null || journalctl -u cron --no-pager -n 5 2>/dev/null) | tail -n 5"
capture 15-cron-growth.txt     "cron 자동 실행 확인 (65초 대기)" "echo before: \$(wc -l < ${AGENT_LOG_DIR}/monitor.log) lines; date; sleep 65; date; echo after: \$(wc -l < ${AGENT_LOG_DIR}/monitor.log) lines; tail -n 2 ${AGENT_LOG_DIR}/monitor.log"
capture 16-report.txt          "보너스1 report.sh"              "su - agent-admin -c '. ${ENV_FILE}; ${AGENT_HOME}/bin/report.sh'"
capture 17-log-retention.txt   "보너스2 log_retention.sh (dry-run + 실행)" "su - agent-admin -c '. ${ENV_FILE}; ${AGENT_HOME}/bin/log_retention.sh --dry-run; ${AGENT_HOME}/bin/log_retention.sh; ls -la ${ARCHIVE_DIR}'"

echo; info "완료. 증빙 파일 목록:"; ls -1 "$OUT"
