#!/usr/bin/env bash
# =============================================================================
# report.sh - monitor.log 통계 리포트 (보너스 1)
#
# 사용법
#   report.sh                                  # 전체 로그 분석
#   report.sh --from "2026-02-25 13:00:00" --to "2026-02-25 14:00:00"
#   report.sh -f "2026-02-25 13:00" -t "2026-02-25 14:00"   # 부분 시각도 허용(접두 비교)
#
# 환경 변수 : MONITOR_LOG_FILE (기본 /var/log/agent-app/monitor.log)
# 종료 코드 : 0 정상, 2 로그 파일 없음/읽기 불가, 3 분석 대상 샘플 0개, 4 인자 오류
# =============================================================================
set -u
set -o pipefail

LOG_FILE="${MONITOR_LOG_FILE:-${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log}"
FROM_TS=""
TO_TS=""

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 4
}

validate_ts() {
  # YYYY-MM-DD[ HH[:MM[:SS]]] 형식만 허용 (로그 타임스탬프와 문자열 비교하므로 접두 형식이면 충분)
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}([ ][0-9]{2}(:[0-9]{2}(:[0-9]{2})?)?)?$ ]]
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      -f|--from) (( $# >= 2 )) || { echo "[ERROR] $1 requires a value" >&2; exit 4; }; FROM_TS="$2"; shift 2 ;;
      -t|--to)   (( $# >= 2 )) || { echo "[ERROR] $1 requires a value" >&2; exit 4; }; TO_TS="$2";   shift 2 ;;
      -h|--help) usage ;;
      *) echo "[ERROR] unknown argument: $1" >&2; usage ;;
    esac
  done
  for ts in "$FROM_TS" "$TO_TS"; do
    if [[ -n "$ts" ]] && ! validate_ts "$ts"; then
      echo "[ERROR] invalid timestamp '$ts' (expected YYYY-MM-DD HH:MM:SS)" >&2
      exit 4
    fi
  done
  if [[ -n "$FROM_TS" && -n "$TO_TS" && "$FROM_TS" > "$TO_TS" ]]; then
    echo "[ERROR] --from must not be later than --to" >&2
    exit 4
  fi
}

main() {
  parse_args "$@"

  if [[ ! -f "$LOG_FILE" ]]; then
    echo "[ERROR] log file not found: ${LOG_FILE}" >&2
    exit 2
  fi
  if [[ ! -r "$LOG_FILE" ]]; then
    echo "[ERROR] log file not readable: ${LOG_FILE} (user=$(id -un))" >&2
    exit 2
  fi

  # 로그 라인 예: [2026-02-25 13:58:01] PID:48291 CPU:10.2% MEM:3.2% DISK_USED:23%
  awk -v from="$FROM_TS" -v to="$TO_TS" '
    function fmt(label, sum, max, maxts, min, mints, n) {
      printf "[%s]\n", label
      printf "  Average : %.1f%%\n", sum / n
      printf "  Maximum : %.1f%% at %s\n", max, maxts
      printf "  Minimum : %.1f%% at %s\n", min, mints
    }
    function in_range(ts) {
      if (from != "" && ts < from) return 0
      if (to   != "" && substr(ts, 1, length(to)) > to) return 0
      return 1
    }
    /^\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] PID:[^ ]+ CPU:[0-9.]+% MEM:[0-9.]+% DISK_USED:[0-9.]+%/ {  # mawk 호환: {n} 수량자 사용 금지
      ts = substr($1 " " $2, 2, 19)
      if (!in_range(ts)) next
      split($4, c, /[:%]/); split($5, m, /[:%]/); split($6, d, /[:%]/)
      cpu = c[2] + 0; mem = m[2] + 0; disk = d[2] + 0
      n++
      if (n == 1) {
        cmax = cmin = cpu; cmaxts = cmints = ts
        mmax = mmin = mem; mmaxts = mmints = ts
        dmax = dmin = disk; dmaxts = dmints = ts
      }
      csum += cpu; if (cpu > cmax) { cmax = cpu; cmaxts = ts } if (cpu < cmin) { cmin = cpu; cmints = ts }
      msum += mem; if (mem > mmax) { mmax = mem; mmaxts = ts } if (mem < mmin) { mmin = mem; mmints = ts }
      dsum += disk; if (disk > dmax) { dmax = disk; dmaxts = ts } if (disk < dmin) { dmin = disk; dmints = ts }
    }
    END {
      print "====== STATISTICS REPORT ======"
      if (from != "" || to != "") printf "[Range] %s ~ %s\n", (from == "" ? "(begin)" : from), (to == "" ? "(end)" : to)
      if (n == 0) { print "[WARNING] no samples found in range"; exit 3 }
      fmt("CPU", csum, cmax, cmaxts, cmin, cmints, n)
      fmt("Memory", msum, mmax, mmaxts, mmin, mmints, n)
      fmt("Disk", dsum, dmax, dmaxts, dmin, dmints, n)
      print "[Samples]"
      printf "  Data Points: %d samples\n", n
    }' "$LOG_FILE"
}

main "$@"
