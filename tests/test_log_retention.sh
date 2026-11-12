#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RET="$REPO_ROOT/scripts/log_retention.sh"

days_ago() {  # days_ago <n> -> touch -t 형식(YYYYMMDDhhmm), GNU/BSD 공통
  if date -v-1d >/dev/null 2>&1; then date -v-"$1"d '+%Y%m%d%H%M'; else date -d "$1 days ago" '+%Y%m%d%H%M'; fi
}

setup() {
  local d; d="$(new_case_dir)"
  mkdir -p "$d/log" "$d/archive"
  echo fresh > "$d/log/monitor.log"
  echo old8  > "$d/log/monitor.20260101_000000.log"; touch -t "$(days_ago 8)" "$d/log/monitor.20260101_000000.log"
  echo old6  > "$d/log/monitor.20260201_000000.log"; touch -t "$(days_ago 6)" "$d/log/monitor.20260201_000000.log"
  echo notlog > "$d/log/notes.txt";                  touch -t "$(days_ago 40)" "$d/log/notes.txt"
  echo gz31 > "$d/archive/a.log.gz";  touch -t "$(days_ago 31)" "$d/archive/a.log.gz"
  echo gz10 > "$d/archive/b.log.gz";  touch -t "$(days_ago 10)" "$d/archive/b.log.gz"
  echo "$d"
}
run_ret() { OUT="$(AGENT_LOG_DIR="$1/log" ARCHIVE_DIR="$1/archive" bash "$RET" "${@:2}" 2>&1)"; RC=$?; }

echo "# log_retention.sh"
echo "## 압축/아카이브/삭제"
d="$(setup)"; run_ret "$d"
assert_eq 0 "$RC" "exit 0"
gzs=( "$d"/archive/monitor.20260101_000000.log.*.gz )
assert_file_exists "${gzs[0]}" "8-day-old log compressed and moved to archive (timestamped name)"
assert_file_missing "$d/log/monitor.20260101_000000.log" "original removed after gzip"
assert_file_exists "$d/log/monitor.20260201_000000.log" "6-day-old log untouched"
assert_file_exists "$d/log/monitor.log" "active log untouched"
assert_file_exists "$d/log/notes.txt" "non-.log files ignored"
assert_file_missing "$d/archive/a.log.gz" "31-day-old archive deleted"
assert_file_exists "$d/archive/b.log.gz" "10-day-old archive kept"
assert_eq "old8" "$(gzip -dc "${gzs[0]}")" "archive content intact"
assert_eq 0 "$(find "$d/archive" -name 'monitor.20260101_000000.log.*.gz' -mtime +0 | wc -l | tr -d ' ')" "archive mtime reset to now (30-day clock starts at archiving)"

echo "## dry-run"
d="$(setup)"; run_ret "$d" --dry-run
assert_eq 0 "$RC" "dry-run exit 0"
assert_contains "$OUT" "(dry-run) would compress+archive" "lists compress targets"
assert_contains "$OUT" "(dry-run) would delete" "lists delete targets"
assert_file_exists "$d/log/monitor.20260101_000000.log" "dry-run changes nothing"
assert_file_exists "$d/archive/a.log.gz" "dry-run deletes nothing"

echo "## 예외 처리"
d="$(new_case_dir)"; run_ret "$d"
assert_eq 2 "$RC" "exit 2 when log dir missing"
assert_contains "$OUT" "[ERROR] log directory not found" "explains missing log dir"

d="$(setup)"; rm -rf "$d/archive"; run_ret "$d"
assert_eq 0 "$RC" "creates missing archive dir"
assert_contains "$OUT" "created archive directory" "reports archive dir creation"
assert_eq 1 "$(ls "$d"/archive/monitor.20260101_000000.log.*.gz | wc -l | tr -d ' ')" "archives after creating dir"
[[ "$(ls -ld "$d/archive" | cut -c8-10)" == "---" ]] && _ok "created archive dir has no 'other' permission" || _fail "archive dir other perms" "$(ls -ld "$d/archive")"

d="$(new_case_dir)"; mkdir -p "$d/log"; echo x > "$d/log/monitor.log"; run_ret "$d"
assert_eq 0 "$RC" "exit 0 with zero targets"
assert_contains "$OUT" "no *.log files older than 7 days" "reports zero compress targets"
assert_contains "$OUT" "no *.gz archives older than 30 days" "reports zero delete targets"

if [[ "$(id -u)" -ne 0 ]]; then
  d="$(setup)"; chmod 500 "$d/log"; run_ret "$d"
  assert_eq 3 "$RC" "exit 3 on insufficient permission"
  chmod 700 "$d/log"
fi

echo "## 임계 일수 재정의"
d="$(setup)"; OUT="$(AGENT_LOG_DIR="$d/log" ARCHIVE_DIR="$d/archive" COMPRESS_AFTER_DAYS=5 bash "$RET" 2>&1)"
assert_eq 1 "$(ls "$d"/archive/monitor.20260201_000000.log.*.gz | wc -l | tr -d ' ')" "COMPRESS_AFTER_DAYS override applies"

echo "## 같은 이름 반복 아카이브"
d="$(setup)"; run_ret "$d"
echo again > "$d/log/monitor.20260101_000000.log"; touch -t "$(days_ago 9)" "$d/log/monitor.20260101_000000.log"; sleep 1; run_ret "$d"
assert_eq 2 "$(ls "$d"/archive/monitor.20260101_000000.log.*.gz | wc -l | tr -d ' ')" "second archive of same name does not overwrite the first"

summary
