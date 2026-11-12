#!/usr/bin/env bash
# 요구사항 3: 환경 변수 고정(/etc/profile.d) + 키 파일 생성
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"
require_root

write_env_file() {
  cat > "$ENV_FILE" <<ENV
# Codyssey B4-1 agent-app 실행 환경 (모든 로그인 셸에 적용). cron 에서는 명시적으로 source 한다.
export AGENT_HOME="${AGENT_HOME}"
export AGENT_PORT="${AGENT_PORT}"
export AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR}"
export AGENT_KEY_PATH="${AGENT_KEY_PATH}"
export AGENT_LOG_DIR="${AGENT_LOG_DIR}"
ENV
  chmod 644 "$ENV_FILE"
  info "환경 변수 파일 작성: $ENV_FILE"; cat "$ENV_FILE"
}

write_key_file() {
  local key_dir; key_dir="$(dirname "$AGENT_KEY_PATH")"
  [[ -d "$key_dir" ]] || die "키 디렉토리가 없다: $key_dir (02-users-groups-dirs.sh 먼저 실행)"
  printf '%s\n' "$AGENT_KEY_VALUE" > "$AGENT_KEY_PATH"
  chown agent-admin:"$GROUP_CORE" "$AGENT_KEY_PATH"
  chmod 660 "$AGENT_KEY_PATH"
  info "키 파일 생성: $AGENT_KEY_PATH"; ls -l "$AGENT_KEY_PATH"; wc -l "$AGENT_KEY_PATH"
}

main() {
  write_env_file
  write_key_file
  echo
  info "검증(agent-admin 로그인 셸 기준):"
  su - agent-admin -c 'env | grep ^AGENT_ | sort; cat "$AGENT_KEY_PATH"'
}
main "$@"
