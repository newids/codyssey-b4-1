#!/usr/bin/env bash
# 호스트 CPU 아키텍처에 맞는 제공 앱 바이너리 이름을 고른다. (source 해서 사용)
#   제공 앱은 인텔용(agent-app-linux-x86)과 ARM/애플 실리콘용(agent-app-linux-arm64) 두 가지다.
#   AGENT_ARCH 를 지정하면 uname -m 대신 그 값을 쓴다 (테스트·강제 지정용).

APP_BIN_X86="agent-app-linux-x86"
APP_BIN_ARM64="agent-app-linux-arm64"

detect_host_arch() { echo "${AGENT_ARCH:-$(uname -m)}"; }

# resolve_app_binary [machine]  → 바이너리 파일명 출력, 미지원이면 1 반환
resolve_app_binary() {
  local machine="${1:-$(detect_host_arch)}"
  case "$machine" in
    x86_64|amd64)  echo "$APP_BIN_X86" ;;
    aarch64|arm64) echo "$APP_BIN_ARM64" ;;
    *) echo "[ERROR] 지원하지 않는 아키텍처: ${machine} (지원: x86_64, aarch64)" >&2; return 1 ;;
  esac
}
