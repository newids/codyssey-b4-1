#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
REPORT="$REPO_ROOT/scripts/report.sh"

d="$(new_case_dir)"
LOG="$d/monitor.log"
cat > "$LOG" <<'L'
[2026-02-25 13:58:01] PID:48291 CPU:10.2% MEM:3.2% DISK_USED:23%
[2026-02-25 13:59:01] PID:48291 CPU:18.7% MEM:5.0% DISK_USED:23%
garbage line that must be ignored
[2026-02-25 14:00:01] PID:48291 CPU:25.3% MEM:9.8% DISK_USED:24%
L

echo "# report.sh"
echo "## 전체 분석"
OUT="$(MONITOR_LOG_FILE="$LOG" bash "$REPORT" 2>&1)"; RC=$?
assert_eq 0 "$RC" "exit 0 with samples"
assert_contains "$OUT" "====== STATISTICS REPORT ======" "prints header"
assert_contains "$OUT" "Average : 18.1%" "CPU average (10.2+18.7+25.3)/3"
assert_contains "$OUT" "Maximum : 25.3% at 2026-02-25 14:00:01" "CPU max with timestamp"
assert_contains "$OUT" "Minimum : 10.2% at 2026-02-25 13:58:01" "CPU min with timestamp"
assert_contains "$OUT" "Average : 6.0%" "MEM average"
assert_contains "$OUT" "Maximum : 24.0% at 2026-02-25 14:00:01" "DISK max"
assert_contains "$OUT" "Data Points: 3 samples" "ignores malformed lines in sample count"

echo "## 구간 분석"
OUT="$(MONITOR_LOG_FILE="$LOG" bash "$REPORT" --from "2026-02-25 13:59:00" --to "2026-02-25 13:59:59" 2>&1)"; RC=$?
assert_eq 0 "$RC" "range exit 0"
assert_contains "$OUT" "Data Points: 1 samples" "filters by --from/--to"
assert_contains "$OUT" "Average : 18.7%" "range CPU average"
OUT="$(MONITOR_LOG_FILE="$LOG" bash "$REPORT" -f "2026-02-25 14:00" 2>&1)"
assert_contains "$OUT" "Data Points: 1 samples" "prefix timestamp accepted for --from"
OUT="$(MONITOR_LOG_FILE="$LOG" bash "$REPORT" -t "2026-02-25 13:59" 2>&1)"
assert_contains "$OUT" "Data Points: 2 samples" "--to is inclusive at prefix granularity"

echo "## 예외"
OUT="$(MONITOR_LOG_FILE="$LOG" bash "$REPORT" --from "2030-01-01 00:00:00" 2>&1)"; RC=$?
assert_eq 3 "$RC" "exit 3 when no samples in range"
assert_contains "$OUT" "[WARNING] no samples found" "warns on empty range"
OUT="$(MONITOR_LOG_FILE="$d/nope.log" bash "$REPORT" 2>&1)"; RC=$?
assert_eq 2 "$RC" "exit 2 when log missing"
OUT="$(MONITOR_LOG_FILE="$LOG" bash "$REPORT" --from "yesterday" 2>&1)"; RC=$?
assert_eq 4 "$RC" "exit 4 on invalid timestamp"
OUT="$(MONITOR_LOG_FILE="$LOG" bash "$REPORT" --from "2026-02-25 14:00:00" --to "2026-02-25 13:00:00" 2>&1)"; RC=$?
assert_eq 4 "$RC" "exit 4 when from > to"
OUT="$(MONITOR_LOG_FILE="$LOG" bash "$REPORT" --bogus 2>&1)"; RC=$?
assert_eq 4 "$RC" "exit 4 on unknown argument"
OUT="$(MONITOR_LOG_FILE="$LOG" timeout 5 bash "$REPORT" --from 2>&1)"; RC=$?
assert_eq 4 "$RC" "exit 4 when --from has no value (no infinite loop)"

summary
