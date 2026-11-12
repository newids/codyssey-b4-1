#!/usr/bin/env python3
"""
agent_app.py - 제공 앱(agent-app.zip)의 **로컬 테스트용 대역(mock)**.

평가 제출 시에는 반드시 미션에서 제공된 실제 앱을 사용한다.
이 파일은 제공 앱 없이 monitor.sh / cron 동작을 미리 검증하기 위한 것으로,
제공 앱과 동일한 환경 변수 계약(AGENT_HOME, AGENT_PORT, AGENT_UPLOAD_DIR,
AGENT_KEY_PATH, AGENT_LOG_DIR)과 Boot Sequence 5단계 출력 형식을 흉내 낸다.
"""
import os
import pwd
import socket
import sys
import time

REQUIRED_ENVS = ("AGENT_HOME", "AGENT_PORT", "AGENT_UPLOAD_DIR", "AGENT_KEY_PATH", "AGENT_LOG_DIR")
EXPECTED_KEY = "agent_api_key_test"


def step(n, title, ok, detail):
    status = "[OK]" if ok else "[FAIL]"
    print(f"[{n}/5] {title} {status}")
    print(f"    ... {detail}")
    if not ok:
        print("Boot sequence aborted.")
        sys.exit(1)


def main():
    sys.stdout.reconfigure(line_buffering=True)  # 파일/파이프로 리다이렉트돼도 즉시 출력
    print("> Starting Agent Boot Sequence...")
    uid = os.getuid()
    name = pwd.getpwuid(uid).pw_name
    step(1, "Checking User Account", uid != 0, f"Running as service user '{name}' (uid={uid})")

    missing = [e for e in REQUIRED_ENVS if not os.environ.get(e)]
    step(2, "Verifying Environment Variables", not missing,
         "All required Envs correct" if not missing else f"Missing: {', '.join(missing)}")

    key_path = os.environ["AGENT_KEY_PATH"]
    try:
        with open(key_path, encoding="utf-8") as f:
            key_ok = f.readline().strip() == EXPECTED_KEY
        key_detail = "Verified key file with correct key string." if key_ok else "Key string mismatch."
    except OSError as exc:
        key_ok, key_detail = False, f"Cannot read key file: {exc}"
    step(3, "Checking Required Files", key_ok and os.path.isdir(os.environ["AGENT_UPLOAD_DIR"]), key_detail)

    port = int(os.environ["AGENT_PORT"])
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(("0.0.0.0", port))
        port_ok, port_detail = True, f"Port {port} is available."
    except OSError as exc:
        port_ok, port_detail = False, f"Port {port} unavailable: {exc}"
    step(4, "Checking Port Availability", port_ok, port_detail)

    log_dir = os.environ["AGENT_LOG_DIR"]
    step(5, "Verifying Log Permission", os.access(log_dir, os.W_OK), f"Log directory is writable: {log_dir}")

    print("-" * 60)
    print("All Boot Checks Passed! Agent READY")
    srv.listen(5)
    srv.settimeout(1.0)
    try:
        while True:
            try:
                conn, _ = srv.accept()
                conn.sendall(b"agent ok\n")
                conn.close()
            except socket.timeout:
                time.sleep(0)
    except KeyboardInterrupt:
        print("\nAgent stopped.")


if __name__ == "__main__":
    main()
