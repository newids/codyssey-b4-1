#!/usr/bin/env bash
# 요구사항 1: SSH 포트 20022 + Root 원격 로그인 차단 + UFW(20022/tcp, 15034/tcp 만 허용)
#
# 잠금(lockout) 방지 순서:
#   1) sshd 설정 변경(백업, 문법 오류 시 자동 복원) → 2) sshd 재시작 → 3) 20022 리슨 확인
#   → 4) UFW 에 20022/15034 허용 후 enable → 5) 20022 리슨이 확인된 경우에만 22 규칙 제거
# ⚠️ root 로 직접 SSH 접속한 상태에서는 실행을 거부한다(--force 로 강제). PermitRootLogin no 가 적용되면
#    다시 들어올 수 없기 때문이다. sudo 가 되는 일반 계정으로 접속해 실행하라.
#    클라우드 VM 이면 보안그룹/네트워크 ACL 에서도 20022 를 열어야 한다.
source "$(dirname "${BASH_SOURCE[0]}")/00-common.sh"
require_root

SSHD_CONFIG=/etc/ssh/sshd_config
DROPIN_DIR=/etc/ssh/sshd_config.d
FORCE=0; [[ "${1:-}" == "--force" ]] && FORCE=1
BACKUP=""

guard_against_lockout() {
  if [[ -n "${SSH_CONNECTION:-}" && -z "${SUDO_USER:-}" && $FORCE -eq 0 ]]; then
    die "root 로 직접 SSH 접속한 세션이다. PermitRootLogin no 적용 후 재접속이 불가능해진다.
       sudo 가능한 일반 계정(예: adduser ops && usermod -aG sudo ops, 키/비밀번호 설정)으로 접속해 실행하거나
       정말 괜찮다면: $0 --force"
  fi
  if ! getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -vqx 'root'; then
    warn "sudo 그룹에 일반 계정이 없다. root 차단 후 관리 작업을 할 계정이 있는지 확인하라"
  fi
}

set_sshd_option() {   # set_sshd_option <Key> <Value>: 대소문자 무시, 기존/주석 줄을 한 줄로 고정. 없으면 첫 Match 블록 앞에 삽입
  local key="$1" value="$2"
  if grep -Eiq "^[#[:space:]]*${key}[[:space:]]" "$SSHD_CONFIG"; then
    sed -i -E "s#^[\\#[:space:]]*${key}[[:space:]].*#${key} ${value}#I" "$SSHD_CONFIG"
  elif grep -Eiq '^[[:space:]]*Match[[:space:]]' "$SSHD_CONFIG"; then
    sed -i -E "0,/^[[:space:]]*[Mm][Aa][Tt][Cc][Hh][[:space:]]/s##${key} ${value}\n&#" "$SSHD_CONFIG"
  else
    printf '%s %s\n' "$key" "$value" >> "$SSHD_CONFIG"
  fi
}

neutralize_dropins() {
  [[ -d "$DROPIN_DIR" ]] || return 0
  local f
  for f in "$DROPIN_DIR"/*.conf; do
    [[ -f "$f" ]] || continue
    if grep -Eiq '^[[:space:]]*(Port|PermitRootLogin)[[:space:]]' "$f"; then
      warn "drop-in $f 에 Port/PermitRootLogin 이 있어 주석 처리한다 (Include 가 먼저 읽혀 우선 적용되므로)"
      cp -a "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)"
      sed -i -E 's#^([[:space:]]*(Port|PermitRootLogin)[[:space:]].*)#\# b4-1 disabled: \1#I' "$f"
    fi
  done
}

configure_sshd() {
  command -v sshd >/dev/null 2>&1 || die "sshd 가 없다. 설치: apt-get install -y openssh-server"
  BACKUP="${SSHD_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
  cp -a "$SSHD_CONFIG" "$BACKUP"
  info "sshd_config 백업: $BACKUP"
  set_sshd_option Port "$SSH_PORT"
  set_sshd_option PermitRootLogin no
  neutralize_dropins
  if ! sshd -t; then
    cp -a "$BACKUP" "$SSHD_CONFIG"
    die "sshd 설정 문법 오류 → 백업을 복원했다. 수동으로 확인: sshd -t"
  fi
  info "sshd 유효 설정:"; sshd -T 2>/dev/null | grep -Ei '^(port|permitrootlogin) '
}

restart_sshd() {
  if [[ ! -d /run/systemd/system ]]; then
    warn "systemd 로 부팅되지 않았다(컨테이너?). service 로 재시작을 시도한다"
    service ssh restart 2>/dev/null || warn "수동 재시작 필요: /usr/sbin/sshd"
    return 0
  fi
  # Ubuntu 22.10+ 는 ssh.socket 이 포트를 소유하므로 소켓 단위도 재시작한다
  if systemctl is-enabled ssh.socket >/dev/null 2>&1 || systemctl is-active ssh.socket >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl restart ssh.socket
  fi
  systemctl restart ssh 2>/dev/null || systemctl restart sshd
}

sshd_listening_on_new_port() {
  ss -tln 2>/dev/null | awk -v p=":${SSH_PORT}$" '$4 ~ p {found=1} END {exit !found}'
}

configure_ufw() {   # configure_ufw <new_port_verified: 0|1>
  local verified="$1"
  if ! command -v ufw >/dev/null 2>&1; then
    info "ufw 설치"; apt-get update -qq && apt-get install -y -qq ufw
  fi
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${SSH_PORT}/tcp"   comment 'SSH (b4-1)'
  ufw allow "${AGENT_PORT}/tcp" comment 'Agent APP (b4-1)'
  if ! ufw --force enable; then
    warn "ufw enable 실패. 컨테이너 환경이면 iptables 권한이 없어 정상이다(VM 에서 수행)"
    return 0
  fi
  if (( verified )); then
    ufw delete allow OpenSSH >/dev/null 2>&1 || true
    ufw delete allow 22/tcp  >/dev/null 2>&1 || true
    ufw delete allow 22      >/dev/null 2>&1 || true
    ufw delete limit 22/tcp  >/dev/null 2>&1 || true
  else
    warn "sshd 가 ${SSH_PORT} 에서 리슨하는 것을 확인하지 못해 22 규칙은 제거하지 않았다. 확인 후 수동 제거: ufw delete allow 22/tcp"
  fi
  info "ufw 상태:"; ufw status verbose
  # 허용 포트는 두 개뿐이어야 한다. 그 외 규칙이 남아 있으면 알려 준다
  local extra
  extra="$(ufw status numbered | grep -E '^\[' | grep -vE "(^|[^0-9])(${SSH_PORT}|${AGENT_PORT})/tcp" || true)"
  if [[ -n "$extra" ]]; then
    warn "20022/15034 외 규칙이 남아 있다. 'ufw delete <번호>' 로 제거하라:"; echo "$extra"
  fi
}

main() {
  guard_against_lockout
  configure_sshd
  restart_sshd
  local verified=0
  if sshd_listening_on_new_port; then
    verified=1; info "sshd 가 ${SSH_PORT} 에서 리슨 중:"; ss -tlnp | grep -E ":${SSH_PORT}\b"
  else
    warn "sshd 가 ${SSH_PORT} 에서 리슨하지 않는다 (컨테이너면 수동 기동: /usr/sbin/sshd). 백업: $BACKUP"
  fi
  configure_ufw "$verified"
  cat <<MSG

[NEXT] 현재 세션은 닫지 말고, 다른 터미널에서 접속 확인:  ssh -p ${SSH_PORT} <user>@<host>
       root 차단 확인:  ssh -p ${SSH_PORT} root@<host>   -> Permission denied
       문제가 있으면 복원:  cp ${BACKUP:-/etc/ssh/sshd_config.bak.*} ${SSHD_CONFIG} && systemctl restart ssh
MSG
}
main "$@"
