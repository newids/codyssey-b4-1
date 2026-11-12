#!/usr/bin/env bash
# monitor.sh 단위/통합 테스트 — 외부 명령은 PATH 가짜(fake)로 대체, /proc 은 파일로 대체
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
MONITOR="$REPO_ROOT/scripts/monitor.sh"

make_fakes() {   # make_fakes <dir>
  local d="$1"; mkdir -p "$d"
  cat > "$d/pgrep" <<'F'
#!/usr/bin/env bash
[[ -n "${FAKE_APP_PID:-}" ]] && { tr ' ' '\n' <<<"$FAKE_APP_PID"; exit 0; }
exit 1
F
  cat > "$d/ss" <<'F'
#!/usr/bin/env bash
[[ "${FAKE_PORT_LISTEN:-0}" == "1" ]] && echo "LISTEN 0 5 0.0.0.0:${FAKE_PORT:-15034} 0.0.0.0:* users:((\"python3\",pid=${FAKE_PORT_PID:-${FAKE_APP_PID:-1}},fd=3))"
exit 0
F
  cat > "$d/df" <<'F'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/root 100 %s %s %s%% /\n' "${FAKE_DISK_USED:-23}" "$((100 - ${FAKE_DISK_USED:-23}))" "${FAKE_DISK_USED:-23}"
F
  cat > "$d/ufw" <<'F'
#!/usr/bin/env bash
[[ "$1" == "status" ]] && echo "Status: ${FAKE_UFW_STATUS:-active}"
F
  # 비root 경로: systemctl is-active ufw + ufw.conf ENABLED=yes 로 판단한다
  cat > "$d/systemctl" <<'F'
#!/usr/bin/env bash
[[ "$*" == *"is-active"*"ufw"* && "${FAKE_UFW_STATUS:-active}" == "active" ]] && exit 0
exit 3
F
  printf 'ENABLED=yes\n' > "$d/ufw.conf"
  chmod +x "$d"/*
}

write_proc() {   # write_proc <dir> <busy1> <total1> <busy2> <total2> <mem_used_pct>
  local d="$1"
  # cpu user nice system idle iowait irq softirq steal
  printf 'cpu %d 0 0 %d 0 0 0 0\n' "$2" "$(( $3 - $2 ))" > "$d/stat1"
  printf 'cpu %d 0 0 %d 0 0 0 0\n' "$4" "$(( $5 - $4 ))" > "$d/stat2"
  local total=1000000 avail
  avail=$(( total - total * $6 / 100 ))
  printf 'MemTotal: %d kB\nMemFree: 1 kB\nMemAvailable: %d kB\n' "$total" "$avail" > "$d/meminfo"
}

run_monitor() {  # run_monitor <case_dir> [env assignments...]; 결과는 OUT / RC
  local d="$1"; shift
  OUT="$(env PATH="$d/fakes:$PATH" \
      MONITOR_PROC_STAT="$d/stat1" MONITOR_PROC_STAT_SECOND="$d/stat2" \
      MONITOR_PROC_MEMINFO="$d/meminfo" MONITOR_CPU_SAMPLE_SEC=0 \
      AGENT_LOG_DIR="$d/log" MONITOR_SKIP_REPORT=1 MONITOR_UFW_CONF="$d/fakes/ufw.conf" \
      "$@" bash "$MONITOR" 2>&1)"
  RC=$?
}

file_size_bytes_t() { [[ -f "$1" ]] && wc -c < "$1" | tr -d ' ' || echo 0; }

setup_case() {   # 정상 상태 기본값: 앱 실행 중, 포트 LISTEN, CPU 10%, MEM 5%, DISK 23%
  local d; d="$(new_case_dir)"
  make_fakes "$d/fakes"; mkdir -p "$d/log"
  write_proc "$d" 100 1000 200 2000 5      # (200-100)/(2000-1000) = 10.0%
  echo "$d"
}

echo "# monitor.sh"

echo "## 정상 경로"
d="$(setup_case)"
run_monitor "$d" FAKE_APP_PID=4242 FAKE_PORT_LISTEN=1
assert_eq 0 "$RC" "exit 0 when process and port are healthy"
assert_contains "$OUT" "[OK] (PID: 4242)" "prints process OK with PID"
assert_contains "$OUT" "Checking port 15034... [OK]" "prints port OK"
assert_contains "$OUT" "ufw is active... [OK]" "prints firewall OK"
assert_contains "$OUT" "CPU Usage : 10.0%" "computes CPU from /proc/stat delta"
assert_contains "$OUT" "MEM Usage : 5.0%" "computes MEM from /proc/meminfo"
assert_contains "$OUT" "DISK Used : 23%" "reads root disk used %"
assert_not_contains "$OUT" "[WARNING]" "no warning under thresholds"
line="$(tail -n1 "$d/log/monitor.log")"
[[ "$line" =~ ^\[[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\]\ PID:4242\ CPU:10\.0%\ MEM:5\.0%\ DISK_USED:23%$ ]] \
  && _ok "log line matches required format" || _fail "log line format" "$line"
assert_eq 1 "$(wc -l < "$d/log/monitor.log" | tr -d ' ')" "exactly one log line appended"

echo "## 프로세스 후보가 여럿이면 포트 소유 PID 를 고른다"
d="$(setup_case)"
run_monitor "$d" FAKE_APP_PID="300 4242" FAKE_PORT_PID=4242 FAKE_PORT_LISTEN=1
assert_contains "$OUT" "[OK] (PID: 4242)" "prefers the candidate that owns the port over a lower PID (e.g. an editor)"

echo "## Health Check 실패"
d="$(setup_case)"
run_monitor "$d" FAKE_PORT_LISTEN=1
assert_eq 1 "$RC" "exit 1 when process is missing"
assert_contains "$OUT" "[FAIL] process" "reports process failure"
assert_file_missing "$d/log/monitor.log" "does not append monitor.log on failure"
assert_contains "$(cat "$d/log/monitor.error.log")" "HEALTH_CHECK_FAIL process" "records failure in error log"

d="$(setup_case)"
run_monitor "$d" FAKE_APP_PID=4242 FAKE_PORT_LISTEN=0
assert_eq 1 "$RC" "exit 1 when port is not listening"
assert_contains "$OUT" "[FAIL] TCP port 15034" "reports port failure"

echo "## flock 잠금"
if command -v flock >/dev/null 2>&1; then
  d="$(setup_case)"
  ( exec 9>>"$d/log/.monitor.lock"; flock 9; sleep 8 ) &
  holder=$!; sleep 0.5
  run_monitor "$d" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1
  assert_eq 1 "$RC" "exit 1 when another run holds the lock beyond the wait"
  assert_contains "$OUT" "lock timeout" "explains lock timeout on stderr (stderr must survive the lock setup)"
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
fi

echo "## PATH 에 sbin 이 없어도(cron) ufw 를 찾는다"
d="$(setup_case)"; mkdir -p "$d/usr/sbin"; mv "$d/fakes/ufw" "$d/usr/sbin/ufw"
# cron 과 같은 최소 PATH 를 주고, 스크립트가 덧붙이는 /usr/sbin 을 가짜 루트로 돌린다
OUT="$(env -i PATH="$d/fakes:/usr/bin:/bin" HOME="$d" MONITOR_PROC_STAT="$d/stat1" MONITOR_PROC_STAT_SECOND="$d/stat2" \
  MONITOR_PROC_MEMINFO="$d/meminfo" MONITOR_CPU_SAMPLE_SEC=0 AGENT_LOG_DIR="$d/log" MONITOR_SKIP_REPORT=1 \
  MONITOR_UFW_CONF="$d/fakes/ufw.conf" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1 bash -c 'sed "s#:/usr/local/sbin:/usr/sbin:/sbin\"#:'"$d"'/usr/sbin\"#" "$0" | bash' "$MONITOR" 2>&1)"
assert_contains "$OUT" "ufw is active... [OK]" "ufw found through the sbin path the script appends"
OUT="$(env -i PATH="$d/fakes:/usr/bin:/bin" HOME="$d" MONITOR_PROC_STAT="$d/stat1" MONITOR_PROC_STAT_SECOND="$d/stat2" \
  MONITOR_PROC_MEMINFO="$d/meminfo" MONITOR_CPU_SAMPLE_SEC=0 AGENT_LOG_DIR="$d/log" MONITOR_SKIP_REPORT=1 \
  MONITOR_UFW_CONF="$d/fakes/ufw.conf" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1 bash -c 'sed "s#:/usr/local/sbin:/usr/sbin:/sbin\"#:'"$d"'/nonexistent\"#" "$0" | bash' "$MONITOR" 2>&1)"
assert_contains "$OUT" "[WARNING] no firewall (ufw/firewalld) found" "without sbin on PATH ufw is not found (proves the fix matters)"
grep -q 'export PATH="${PATH:-/usr/bin:/bin}:/usr/local/sbin:/usr/sbin:/sbin"' "$MONITOR" && _ok "script appends sbin dirs to PATH" || _fail "script PATH line changed; update this test"
mv "$d/usr/sbin/ufw" "$d/fakes/ufw"

echo "## 방화벽 비활성 → 경고만"
d="$(setup_case)"
run_monitor "$d" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1 FAKE_UFW_STATUS=inactive
assert_eq 0 "$RC" "firewall inactive does not change exit code"
assert_contains "$OUT" "[WARNING] ufw is INACTIVE" "prints firewall warning"

echo "## 임계값 경고"
d="$(setup_case)"
write_proc "$d" 0 1000 253 2000 12        # CPU 25.3%, MEM 12%
run_monitor "$d" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1 FAKE_DISK_USED=81
assert_eq 0 "$RC" "warnings do not change exit code"
assert_contains "$OUT" "[WARNING] CPU threshold exceeded (25.3% > 20%)" "CPU warning"
assert_contains "$OUT" "[WARNING] MEM threshold exceeded (12.0% > 10%)" "MEM warning"
assert_contains "$OUT" "[WARNING] DISK threshold exceeded (81% > 80%)" "DISK warning"

d="$(setup_case)"
write_proc "$d" 0 1000 200 2000 10        # 경계값: CPU 20.0, MEM 10.0 → 경고 없음
run_monitor "$d" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1 FAKE_DISK_USED=80
assert_not_contains "$OUT" "[WARNING]" "no warning exactly at thresholds (strict >)"

echo "## 로그 회전 (10MB / 10개)"
d="$(setup_case)"
head -c $((10 * 1024 * 1024)) /dev/zero | tr '\0' 'x' > "$d/log/monitor.log"
run_monitor "$d" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1
assert_contains "$OUT" "[INFO] Log rotated:" "rotates when size >= 10MB"
assert_eq 1 "$(wc -l < "$d/log/monitor.log" | tr -d ' ')" "fresh monitor.log has one line after rotation"
assert_eq 1 "$(ls "$d/log"/monitor.[0-9]*_[0-9]*.log | wc -l | tr -d ' ')" "one rotated file created"

d="$(setup_case)"
head -c $((10 * 1024 * 1024)) /dev/zero > "$d/log/monitor.log"
for i in $(seq 1 12); do
  f="$d/log/monitor.2026010${i}_000000.log"; [[ $i -ge 10 ]] && f="$d/log/monitor.202601${i}_000000.log"
  echo old > "$f"; touch -t "2026010100$(printf '%02d' "$i")" "$f"
done
run_monitor "$d" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1
assert_eq 9 "$(ls "$d/log"/monitor.[0-9]*_[0-9]*.log | wc -l | tr -d ' ')" "keeps only 9 rotated files (10 incl. monitor.log)"
assert_eq 10 "$(ls "$d/log"/monitor*.log | wc -l | tr -d ' ')" "total monitor*.log files is 10"

d="$(setup_case)"
head -c $((10 * 1024 * 1024)) /dev/zero > "$d/log/monitor.error.log"
head -c $((10 * 1024 * 1024)) /dev/zero > "$d/log/monitor.cron.log"
run_monitor "$d" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1
assert_eq 0 "$(file_size_bytes_t "$d/log/monitor.error.log")" "monitor.error.log is rotated at 10MB too"
assert_eq 0 "$(file_size_bytes_t "$d/log/monitor.cron.log")" "monitor.cron.log is rotated at 10MB too"

echo "## 로그 디렉토리 문제"
d="$(setup_case)"; rm -rf "$d/log"
run_monitor "$d" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1
assert_eq 1 "$RC" "exit 1 when log dir missing"
assert_contains "$OUT" "log directory does not exist" "explains missing log dir"

if [[ "$(id -u)" -ne 0 ]]; then
  d="$(setup_case)"; chmod 500 "$d/log"
  run_monitor "$d" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1
  assert_eq 1 "$RC" "exit 1 when log dir not writable"
  assert_contains "$OUT" "no write permission" "explains permission error"
  chmod 700 "$d/log"
fi

echo "## report.sh 연동"
d="$(setup_case)"
cat > "$d/report.sh" <<'F'
#!/usr/bin/env bash
echo "REPORT CALLED log=$MONITOR_LOG_FILE"
F
chmod +x "$d/report.sh"
OUT="$(env PATH="$d/fakes:$PATH" MONITOR_PROC_STAT="$d/stat1" MONITOR_PROC_STAT_SECOND="$d/stat2" \
  MONITOR_PROC_MEMINFO="$d/meminfo" MONITOR_CPU_SAMPLE_SEC=0 AGENT_LOG_DIR="$d/log" \
  MONITOR_REPORT_SCRIPT="$d/report.sh" FAKE_APP_PID=1 FAKE_PORT_LISTEN=1 bash "$MONITOR" 2>&1)"
assert_contains "$OUT" "REPORT CALLED log=$d/log/monitor.log" "invokes report.sh with the log path"

summary
