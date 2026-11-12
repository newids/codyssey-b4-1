#!/usr/bin/env bash
# =============================================================================
# monitor.sh - 시스템 상태 수집 및 로깅 스크립트 (Codyssey B4-1)
#
# 배치 경로 : $AGENT_HOME/bin/monitor.sh
# 소유/권한 : agent-dev:agent-core 750
# 실행 주체 : agent-admin (crontab 매분) 또는 agent-core 그룹 사용자 수동 실행
#
# 동작 순서
#   1. Health Check  : 앱 프로세스 / TCP 포트 LISTEN 확인  -> 실패 시 exit 1
#   2. 상태 점검     : 방화벽(UFW/firewalld) 활성 여부      -> 비활성 시 [WARNING] 만
#   3. 자원 수집     : CPU % / MEM % / DISK(root) Used %
#   4. 임계값 경고   : CPU>20, MEM>10, DISK>80              -> [WARNING] 만
#   5. 로그 기록     : [YYYY-MM-DD HH:MM:SS] PID:.. CPU:..% MEM:..% DISK_USED:..%
#   6. 로그 용량 관리: 10MB 초과 시 회전, 최대 10개 파일 유지
#
# 종료 코드 : 0 정상, 1 Health Check 실패 또는 로그 기록 불가
# =============================================================================
set -u
set -o pipefail
# cron 과 su - 의 PATH 에는 sbin 이 없어 ufw 를 못 찾는다. 기존 PATH 뒤에 sbin 계열을 보강한다.
export PATH="${PATH:-/usr/bin:/bin}:/usr/local/sbin:/usr/sbin:/sbin"

# ----- 설정 (환경 변수로 재정의 가능) ----------------------------------------
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
# 제공 앱 파일명. 확장 정규식(pgrep -f). 기본값은 python 앱명과 배포 바이너리명 모두 대응
AGENT_APP_NAME="${AGENT_APP_NAME:-agent_app\.py|agent-app-linux}"
LOG_FILE="${MONITOR_LOG_FILE:-${AGENT_LOG_DIR}/monitor.log}"
ERROR_LOG_FILE="${MONITOR_ERROR_LOG_FILE:-${AGENT_LOG_DIR}/monitor.error.log}"
REPORT_SCRIPT="${MONITOR_REPORT_SCRIPT:-${AGENT_HOME}/bin/report.sh}"

# 테스트 용이성을 위한 입력 소스 재정의 지점 (운영 환경에서는 기본값 사용)
PROC_STAT_FILE="${MONITOR_PROC_STAT:-/proc/stat}"
PROC_MEMINFO_FILE="${MONITOR_PROC_MEMINFO:-/proc/meminfo}"
CPU_SAMPLE_SEC="${MONITOR_CPU_SAMPLE_SEC:-1}"
UFW_CONF_FILE="${MONITOR_UFW_CONF:-/etc/ufw/ufw.conf}"

readonly CPU_THRESHOLD=20
readonly MEM_THRESHOLD=10
readonly DISK_THRESHOLD=80
readonly LOG_MAX_BYTES=$((10 * 1024 * 1024))   # 10MB
readonly LOG_KEEP_FILES=10                      # monitor.log 포함 총 10개
readonly EXIT_OK=0
readonly EXIT_HEALTH_FAIL=1

now() { date '+%Y-%m-%d %H:%M:%S'; }

log_error_file() {
  # 실패 사유를 별도 에러 로그에 남긴다 (monitor.log 포맷을 오염시키지 않기 위함)
  local dir
  dir="$(dirname "$ERROR_LOG_FILE")"
  if [[ -d "$dir" && -w "$dir" ]]; then
    printf '[%s] %s\n' "$(now)" "$*" >> "$ERROR_LOG_FILE" 2>/dev/null || true
  fi
}

fail() {
  echo "[FAIL] $*" >&2
  log_error_file "HEALTH_CHECK_FAIL $*"
  exit "$EXIT_HEALTH_FAIL"
}

# ----- 1. Health Check ---------------------------------------------------------
port_owner_pids() {
  # 해당 포트를 LISTEN 중인 프로세스 PID 목록 (비root 는 자기 프로세스만 보인다)
  command -v ss >/dev/null 2>&1 || return 0
  ss -tlnpH 2>/dev/null | awk -v p=":${AGENT_PORT}$" '$4 ~ p' | grep -oE 'pid=[0-9]+' | cut -d= -f2
}

find_app_pid() {
  # 명령줄 패턴(pgrep -f)으로 후보를 모은 뒤, 자기 자신/부모 셸을 제외한다.
  # 후보 중 실제로 포트를 LISTEN 하는 PID 가 있으면 그것을 우선한다(편집기 등 오탐 방지).
  local pid owners candidates=()
  for pid in $(pgrep -f -- "$AGENT_APP_NAME" 2>/dev/null); do
    [[ "$pid" == "$$" || "$pid" == "$PPID" ]] && continue
    candidates+=("$pid")
  done
  (( ${#candidates[@]} == 0 )) && return 1
  owners="$(port_owner_pids)"
  for pid in "${candidates[@]}"; do
    if grep -qx "$pid" <<<"$owners"; then echo "$pid"; return 0; fi
  done
  echo "${candidates[0]}"
}

is_port_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -tlnH 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {found=1} END {exit !found}'
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -tln 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {found=1} END {exit !found}'
    return $?
  fi
  # 최후 수단: bash 내장 /dev/tcp 로 연결 시도
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null
}

health_check() {
  echo "[HEALTH CHECK]"
  printf "  Checking process '%s'... " "${AGENT_APP_NAME//\\/}"
  if ! APP_PID="$(find_app_pid)"; then
    echo "[FAIL]"
    fail "process '${AGENT_APP_NAME}' is not running"
  fi
  echo "[OK] (PID: ${APP_PID})"

  printf "  Checking port %s... " "$AGENT_PORT"
  if ! is_port_listening "$AGENT_PORT"; then
    echo "[FAIL]"
    fail "TCP port ${AGENT_PORT} is not in LISTEN state"
  fi
  echo "[OK]"
}

# ----- 2. 방화벽 상태 점검 (경고만) -----------------------------------------
firewall_status() {
  # 출력: "ufw active" | "ufw inactive" | "firewalld active" | "firewalld inactive" | "none"
  if command -v ufw >/dev/null 2>&1; then
    # ufw status 는 root 전용. 비root 에서 sudo 를 매분 시도하면 auth.log 가 오염되므로 하지 않는다.
    local out=""
    if [[ "$(id -u)" -eq 0 ]]; then
      out="$(ufw status 2>/dev/null)"
    fi
    if [[ -n "$out" ]]; then
      if grep -q '^Status: active' <<<"$out"; then echo "ufw active"; else echo "ufw inactive"; fi
      return
    fi
    # 비root 폴백: 서비스 상태 + /etc/ufw/ufw.conf 의 ENABLED 값
    if systemctl is-active --quiet ufw 2>/dev/null \
       && grep -qs '^ENABLED=yes' "$UFW_CONF_FILE"; then
      echo "ufw active"
    else
      echo "ufw inactive"
    fi
    return
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state >/dev/null 2>&1 || systemctl is-active --quiet firewalld 2>/dev/null; then
      echo "firewalld active"
    else
      echo "firewalld inactive"
    fi
    return
  fi
  echo "none"
}

firewall_check() {
  echo "[FIREWALL CHECK]"
  local status
  status="$(firewall_status)"
  case "$status" in
    *" active")   echo "  ${status%% *} is active... [OK]" ;;
    *" inactive") echo "  [WARNING] ${status%% *} is INACTIVE (inbound ports are not filtered)" ;;
    *)            echo "  [WARNING] no firewall (ufw/firewalld) found on this system" ;;
  esac
}

# ----- 3. 자원 수집 -------------------------------------------------------------
read_cpu_counters() {
  # 출력: "<busy> <total>" (jiffies 누적값). 인자로 읽을 파일을 지정할 수 있다(테스트용)
  local src="${1:-$PROC_STAT_FILE}"
  awk '/^cpu / {
    idle = $5 + $6; total = 0
    for (i = 2; i <= NF; i++) total += $i
    printf "%d %d\n", total - idle, total
  }' "$src"
}

cpu_usage_percent() {
  local b1 t1 b2 t2
  read -r b1 t1 < <(read_cpu_counters)
  sleep "$CPU_SAMPLE_SEC"
  read -r b2 t2 < <(read_cpu_counters "${MONITOR_PROC_STAT_SECOND:-}")
  awk -v b1="$b1" -v t1="$t1" -v b2="$b2" -v t2="$t2" 'BEGIN {
    dt = t2 - t1
    if (dt <= 0) { printf "0.0\n" } else { printf "%.1f\n", (b2 - b1) * 100 / dt }
  }'
}

mem_usage_percent() {
  awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2}
       END { if (t > 0) printf "%.1f\n", (t - a) * 100 / t; else print "0.0" }' "$PROC_MEMINFO_FILE"
}

disk_usage_percent() {
  # Root 파티션 Used %. df -P 로 출력 형식을 고정(POSIX)
  df -P / 2>/dev/null | awk 'NR==2 { gsub("%", "", $5); print $5 }'
}

# ----- 4. 임계값 경고 -------------------------------------------------------------
warn_if_over() {
  local label="$1" value="$2" limit="$3" unit="$4"
  if awk -v v="$value" -v l="$limit" 'BEGIN { exit !(v > l) }'; then
    echo "  [WARNING] ${label} threshold exceeded (${value}${unit} > ${limit}${unit})"
  fi
}

# ----- 5~6. 로그 기록 및 용량 관리 ------------------------------------------------
file_size_bytes() { [[ -f "$1" ]] && wc -c < "$1" | tr -d ' ' || echo 0; }

rotate_log_if_needed() {   # rotate_log_if_needed [파일] (기본: monitor.log)
  local target="${1:-$LOG_FILE}" size
  size="$(file_size_bytes "$target")"
  (( size < LOG_MAX_BYTES )) && return 0

  local base dir rotated
  dir="$(dirname "$target")"
  base="$(basename "$target" .log)"
  rotated="${dir}/${base}.$(date '+%Y%m%d_%H%M%S').log"
  [[ -e "$rotated" ]] && rotated="${dir}/${base}.$(date '+%Y%m%d_%H%M%S')_$$.log"
  mv -f "$target" "$rotated"
  echo "  [INFO] Log rotated: ${rotated}"

  # 회전본은 최신순으로 (LOG_KEEP_FILES - 1)개만 유지, 나머지 삭제
  local keep=$((LOG_KEEP_FILES - 1))
  ls -1t "${dir}/${base}".[0-9]*_[0-9]*.log 2>/dev/null | tail -n +$((keep + 1)) | while read -r old; do
    rm -f -- "$old" && echo "  [INFO] Old log removed: ${old}"
  done
}

append_log() {
  local line="$1"
  local dir
  dir="$(dirname "$LOG_FILE")"
  if [[ ! -d "$dir" ]]; then
    echo "[FAIL] log directory does not exist: ${dir}" >&2
    exit "$EXIT_HEALTH_FAIL"
  fi
  if [[ ! -w "$dir" ]] || { [[ -f "$LOG_FILE" ]] && [[ ! -w "$LOG_FILE" ]]; }; then
    echo "[FAIL] no write permission on log: ${LOG_FILE} (user=$(id -un))" >&2
    exit "$EXIT_HEALTH_FAIL"
  fi
  rotate_log_if_needed "$LOG_FILE"
  # 같은 디렉토리의 보조 로그도 무한 증가하지 않도록 같은 기준으로 회전
  local aux
  for aux in "$ERROR_LOG_FILE" "${dir}/monitor.cron.log"; do
    [[ -f "$aux" ]] && rotate_log_if_needed "$aux"
  done
  printf '%s\n' "$line" >> "$LOG_FILE"
  echo "[INFO] Log appended: ${LOG_FILE}"
}

# ----- main -----------------------------------------------------------------------
acquire_lock() {
  # 수동 실행과 cron 이 겹쳐 같은 초에 회전하는 경쟁을 막는다 (flock 없는 환경에서는 생략)
  command -v flock >/dev/null 2>&1 || return 0
  local lock_dir; lock_dir="$(dirname "$LOG_FILE")"
  [[ -d "$lock_dir" && -w "$lock_dir" ]] || return 0
  # 주의: 'exec 9>>f 2>/dev/null' 처럼 쓰면 stderr 가 영구히 /dev/null 로 바뀐다. 그룹으로 감싸 일시 적용한다
  { exec 9>>"${lock_dir}/.monitor.lock"; } 2>/dev/null || return 0
  if ! flock -w 5 9; then
    echo "[FAIL] another monitor.sh is still running (lock timeout)" >&2
    exit "$EXIT_HEALTH_FAIL"
  fi
}

main() {
  acquire_lock
  echo "====== SYSTEM MONITOR RESULT ======"
  health_check
  firewall_check

  echo "[RESOURCE MONITORING]"
  local cpu mem disk
  cpu="$(cpu_usage_percent)"
  mem="$(mem_usage_percent)"
  disk="$(disk_usage_percent)"
  disk="${disk:-0}"
  echo "  CPU Usage : ${cpu}%"
  echo "  MEM Usage : ${mem}%"
  echo "  DISK Used : ${disk}%"
  warn_if_over "CPU"  "$cpu"  "$CPU_THRESHOLD"  "%"
  warn_if_over "MEM"  "$mem"  "$MEM_THRESHOLD"  "%"
  warn_if_over "DISK" "$disk" "$DISK_THRESHOLD" "%"

  append_log "[$(now)] PID:${APP_PID} CPU:${cpu}% MEM:${mem}% DISK_USED:${disk}%"

  if [[ -z "${MONITOR_SKIP_REPORT:-}" && -x "$REPORT_SCRIPT" ]]; then
    MONITOR_LOG_FILE="$LOG_FILE" "$REPORT_SCRIPT" || true
  fi
  exit "$EXIT_OK"
}

main "$@"
