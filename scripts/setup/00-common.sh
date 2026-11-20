#!/usr/bin/env bash
# 설정 스크립트 공통 변수/함수. 각 setup 스크립트가 source 한다.
# 미션 고정값은 여기서만 바꾼다.
set -u
set -o pipefail

export SSH_PORT="${SSH_PORT:-20022}"
export AGENT_PORT="${AGENT_PORT:-15034}"
export AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
export AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR:-${AGENT_HOME}/upload_files}"
# 제공 앱은 AGENT_KEY_PATH 를 "키 디렉토리"로 보고 그 안의 secret.key 를 읽는다
#   (미션 문서의 api_keys/t_secret.key 표기와 다르다 → 실제 앱 동작 기준)
export AGENT_KEY_PATH="${AGENT_KEY_PATH:-${AGENT_HOME}/api_keys}"
export AGENT_KEY_FILE="${AGENT_KEY_PATH}/secret.key"
export AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
export ARCHIVE_DIR="${ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"   # 보너스 2
export AGENT_KEY_VALUE="agent_api_key_test"
export ENV_FILE="/etc/profile.d/agent-env.sh"

export USERS=(agent-admin agent-dev agent-test)
export GROUP_COMMON="agent-common"   # admin, dev, test
export GROUP_CORE="agent-core"       # admin, dev

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require_root() { [[ "$(id -u)" -eq 0 ]] || die "run as root: sudo $0"; }
