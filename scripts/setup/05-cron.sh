#!/usr/bin/env bash
# 요구사항 5: agent-admin crontab 에 monitor.sh 매분 실행 등록
#   + 보너스 2: log_retention.sh 매일 03:00 실행 등록 (7일 경과 압축·이동, 30일 경과 삭제)
#   - 환경 변수 파일을 source 한 뒤 실행 (cron 은 로그인 셸 환경을 상속하지 않는다)
#   - 표준출력은 버리고 표준에러만 monitor.cron.log 에 남겨 디스크 낭비를 막는다
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"
require_root

# [ -r ] 가드: cron 의 /bin/sh(dash) 에서 source 실패가 전체 명령을 중단시키지 않게 한다.
# MONITOR_SKIP_REPORT=1: 매분 통계 리포트를 계산해 버리는 낭비를 막는다(수동 실행 시에는 출력됨).
CRON_LINE="* * * * * [ -r ${ENV_FILE} ] && . ${ENV_FILE}; MONITOR_SKIP_REPORT=1 ${AGENT_HOME}/bin/monitor.sh >/dev/null 2>>${AGENT_LOG_DIR}/monitor.cron.log"
MARK="# b4-1 monitor"
RETENTION_LINE="0 3 * * * [ -r ${ENV_FILE} ] && . ${ENV_FILE}; ${AGENT_HOME}/bin/log_retention.sh >>${AGENT_LOG_DIR}/retention.cron.log 2>&1"
RETENTION_MARK="# b4-1 log retention (daily 03:00)"

if ! command -v crontab >/dev/null 2>&1; then
  info "cron 설치"; apt-get update -qq && apt-get install -y -qq cron
fi
if [[ -d /run/systemd/system ]]; then
  systemctl enable --now cron >/dev/null 2>&1 || true
else
  service cron start >/dev/null 2>&1 || true
fi

# 재실행해도 중복 등록되지 않도록 이전 b4-1 라인을 지우고 다시 쓴다.
existing="$(crontab -l -u agent-admin 2>/dev/null \
  | grep -vF "$MARK" | grep -vF "$RETENTION_MARK" \
  | grep -v 'bin/monitor.sh' | grep -v 'bin/log_retention.sh' || true)"
{
  [[ -n "$existing" ]] && printf '%s\n' "$existing"
  printf '%s\n%s\n' "$MARK" "$CRON_LINE"
  printf '%s\n%s\n' "$RETENTION_MARK" "$RETENTION_LINE"
} | crontab -u agent-admin -
info "등록된 crontab (agent-admin):"; crontab -l -u agent-admin

cat <<MSG

[NEXT] 1~2분 뒤 자동 누적 확인:
   tail -n 3 ${AGENT_LOG_DIR}/monitor.log ; sleep 65 ; tail -n 3 ${AGENT_LOG_DIR}/monitor.log
   grep CRON /var/log/syslog | tail   (또는 journalctl -u cron -n 5)
[NEXT] 보존 정책 즉시 확인 (03:00 을 기다리지 않고):
   sudo su - agent-admin -c '\$AGENT_HOME/bin/log_retention.sh --dry-run'
MSG
