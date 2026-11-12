#!/usr/bin/env bash
# 요구사항 2: 계정/그룹/디렉토리/권한(ACL)
#   agent-common = admin, dev, test   -> upload_files R/W
#   agent-core   = admin, dev         -> api_keys, /var/log/agent-app R/W (ONLY)
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"
require_root

ensure_acl_tools() {
  command -v setfacl >/dev/null 2>&1 && return 0
  info "acl 패키지 설치"; apt-get update -qq && apt-get install -y -qq acl
}

create_groups_and_users() {
  local g u
  for g in "$GROUP_COMMON" "$GROUP_CORE"; do
    getent group "$g" >/dev/null || { groupadd "$g"; info "group created: $g"; }
  done
  for u in "${USERS[@]}"; do
    if ! id "$u" >/dev/null 2>&1; then
      useradd -m -s /bin/bash "$u"
      info "user created: $u  (비밀번호는 필요 시 'passwd $u' 로 설정)"
    fi
  done
  usermod -aG "$GROUP_COMMON" agent-admin
  usermod -aG "$GROUP_COMMON" agent-dev
  usermod -aG "$GROUP_COMMON" agent-test
  usermod -aG "$GROUP_CORE"   agent-admin
  usermod -aG "$GROUP_CORE"   agent-dev
  # agent-test 가 실수로 core 에 들어가 있으면 제거(최소 권한)
  if id -nG agent-test | tr ' ' '\n' | grep -qx "$GROUP_CORE"; then
    gpasswd -d agent-test "$GROUP_CORE"
  fi
}

create_directories() {
  # AGENT_HOME: 소유 agent-admin, 그룹 agent-core. common 그룹은 통과(x)만 허용해 upload_files 에 닿게 한다
  install -d -o agent-admin -g "$GROUP_CORE" -m 750 "$AGENT_HOME"
  setfacl -m "g:${GROUP_COMMON}:--x" "$AGENT_HOME"
  # 홈 디렉토리(기본 750)도 통과 권한 필요
  setfacl -m "g:${GROUP_COMMON}:--x" /home/agent-admin

  # upload_files: group=agent-common R/W. setgid(2) 로 새 파일의 그룹을 유지, 기본 ACL 로 상속
  install -d -o agent-admin -g "$GROUP_COMMON" -m 2770 "$AGENT_UPLOAD_DIR"
  setfacl -m "g:${GROUP_COMMON}:rwx" -m "o::---" "$AGENT_UPLOAD_DIR"
  setfacl -d -m "g:${GROUP_COMMON}:rwx" -d -m "o::---" "$AGENT_UPLOAD_DIR"

  # api_keys: group=agent-core ONLY
  local key_dir; key_dir="$(dirname "$AGENT_KEY_PATH")"
  install -d -o agent-admin -g "$GROUP_CORE" -m 2770 "$key_dir"
  setfacl -m "g:${GROUP_CORE}:rwx" -m "o::---" "$key_dir"
  setfacl -d -m "g:${GROUP_CORE}:rwx" -d -m "o::---" "$key_dir"

  # /var/log/agent-app: group=agent-core ONLY
  install -d -o agent-admin -g "$GROUP_CORE" -m 2770 "$AGENT_LOG_DIR"
  setfacl -m "g:${GROUP_CORE}:rwx" -m "o::---" "$AGENT_LOG_DIR"
  setfacl -d -m "g:${GROUP_CORE}:rwx" -d -m "o::---" "$AGENT_LOG_DIR"

  # (보너스 2) 아카이브 디렉토리: 로그와 같은 정책(core ONLY). 상위 /var/log/monitor 는 통과만 허용
  install -d -o root -g "$GROUP_CORE" -m 750 "$(dirname "$(dirname "$ARCHIVE_DIR")")"
  install -d -o agent-admin -g "$GROUP_CORE" -m 2770 "$(dirname "$ARCHIVE_DIR")" "$ARCHIVE_DIR"
  setfacl -m "g:${GROUP_CORE}:rwx" -m "o::---" "$(dirname "$ARCHIVE_DIR")" "$ARCHIVE_DIR"
  setfacl -d -m "g:${GROUP_CORE}:rwx" -d -m "o::---" "$ARCHIVE_DIR"

  # bin: 작성자 agent-dev, 실행자 agent-admin(agent-core) -> 750
  install -d -o agent-dev -g "$GROUP_CORE" -m 750 "${AGENT_HOME}/bin"
}

show_result() {
  echo; info "계정/그룹:"
  for u in "${USERS[@]}"; do id "$u"; done
  getent group "$GROUP_COMMON" "$GROUP_CORE"
  echo; info "디렉토리/권한:"
  ls -ld "$AGENT_HOME" "$AGENT_UPLOAD_DIR" "$(dirname "$AGENT_KEY_PATH")" "$AGENT_LOG_DIR" "${AGENT_HOME}/bin" "$ARCHIVE_DIR"
  getfacl -p "$AGENT_UPLOAD_DIR" "$(dirname "$AGENT_KEY_PATH")" "$AGENT_LOG_DIR" 2>/dev/null
}

main() {
  ensure_acl_tools
  create_groups_and_users
  create_directories
  show_result
}
main "$@"
