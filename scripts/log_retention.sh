#!/usr/bin/env bash
# =============================================================================
# log_retention.sh - 시간 기반 로그 보존 정책 (보너스 2)
#
#   1) /var/log/agent-app/*.log 중 7일 이상 경과 파일 -> gzip 압축
#   2) 압축본을 /var/log/monitor/agent-app/archive/ 로 이동
#   3) archive/*.gz 중 30일 이상 경과 파일 삭제
#
# 예외 처리 : 디렉토리 미존재 / 권한 부족 / 대상 0개 -> 경고 출력 후 안전 종료
# 환경 변수 : AGENT_LOG_DIR, ARCHIVE_DIR, COMPRESS_AFTER_DAYS(7), DELETE_AFTER_DAYS(30)
# 옵션      : --dry-run (실제 변경 없이 대상만 출력)
# 종료 코드 : 0 정상(대상 0개 포함), 2 디렉토리 미존재/생성 불가, 3 권한 부족
# =============================================================================
set -u
set -o pipefail

LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"
COMPRESS_AFTER_DAYS="${COMPRESS_AFTER_DAYS:-7}"
DELETE_AFTER_DAYS="${DELETE_AFTER_DAYS:-30}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

now() { date '+%Y-%m-%d %H:%M:%S'; }
info() { echo "[$(now)] [INFO] $*"; }
warn() { echo "[$(now)] [WARNING] $*" >&2; }
err()  { echo "[$(now)] [ERROR] $*" >&2; }

ensure_dirs() {
  if [[ ! -d "$LOG_DIR" ]]; then
    err "log directory not found: ${LOG_DIR}"; exit 2
  fi
  if [[ ! -r "$LOG_DIR" || ! -w "$LOG_DIR" ]]; then
    err "insufficient permission on ${LOG_DIR} (user=$(id -un))"; exit 3
  fi
  if [[ ! -d "$ARCHIVE_DIR" ]]; then
    if (( DRY_RUN )); then
      warn "archive directory missing (would create): ${ARCHIVE_DIR}"
      return 0
    fi
    # 로그 디렉토리와 같은 정책(그룹만 접근)으로 생성. umask 로 other 권한을 막는다
    if ! (umask 007 && mkdir -p "$ARCHIVE_DIR") 2>/dev/null; then
      err "cannot create archive directory: ${ARCHIVE_DIR}"; exit 2
    fi
    info "created archive directory: ${ARCHIVE_DIR}"
  fi
  if [[ ! -w "$ARCHIVE_DIR" ]]; then
    err "insufficient permission on ${ARCHIVE_DIR} (user=$(id -un))"; exit 3
  fi
}

compress_and_archive() {
  local count=0 f gz dest stamp
  stamp="$(date '+%Y%m%d_%H%M%S')"
  # 활성 로그(monitor.log, monitor.error.log 등)도 7일간 쓰기 없음이면 대상이 된다
  while IFS= read -r -d '' f; do
    count=$((count + 1))
    if (( DRY_RUN )); then
      info "(dry-run) would compress+archive: ${f}"; continue
    fi
    if ! gzip -f -- "$f" 2>/dev/null; then
      warn "compress failed (skipped): ${f}"; continue
    fi
    gz="${f}.gz"
    # 같은 이름(monitor.error.log 등)이 반복 아카이브돼도 덮어쓰지 않도록 시각을 붙인다
    dest="${ARCHIVE_DIR}/$(basename "$f").${stamp}.gz"
    [[ -e "$dest" ]] && dest="${ARCHIVE_DIR}/$(basename "$f").${stamp}_$$.gz"
    if mv -n -- "$gz" "$dest" 2>/dev/null && [[ ! -e "$gz" ]]; then
      touch -- "$dest" 2>/dev/null   # 30일 보존 시계는 '아카이브된 시각'부터 (gzip 은 원본 mtime 을 유지함)
      info "archived: ${f} -> ${dest}"
    else
      warn "move failed, compressed file left in place: ${gz}"
    fi
  done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime "+$((COMPRESS_AFTER_DAYS - 1))" -print0 2>/dev/null)
  if (( count == 0 )); then
    info "no *.log files older than ${COMPRESS_AFTER_DAYS} days in ${LOG_DIR}"
  fi
}

purge_old_archives() {
  [[ -d "$ARCHIVE_DIR" ]] || return 0
  local count=0 f
  while IFS= read -r -d '' f; do
    count=$((count + 1))
    if (( DRY_RUN )); then
      info "(dry-run) would delete: ${f}"; continue
    fi
    if rm -f -- "$f" 2>/dev/null; then
      info "deleted archive: ${f}"
    else
      warn "delete failed (skipped): ${f}"
    fi
  done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.gz' -mtime "+$((DELETE_AFTER_DAYS - 1))" -print0 2>/dev/null)
  if (( count == 0 )); then
    info "no *.gz archives older than ${DELETE_AFTER_DAYS} days in ${ARCHIVE_DIR}"
  fi
}

main() {
  info "log retention start (log=${LOG_DIR}, archive=${ARCHIVE_DIR}, compress>${COMPRESS_AFTER_DAYS}d, delete>${DELETE_AFTER_DAYS}d, dry-run=${DRY_RUN})"
  ensure_dirs
  compress_and_archive
  purge_old_archives
  info "log retention done"
}

main "$@"
