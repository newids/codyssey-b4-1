#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
LIB="$REPO_ROOT/scripts/setup/app-arch.sh"
RUN="$REPO_ROOT/scripts/setup/run-app.sh"
INSTALL="$REPO_ROOT/scripts/setup/install-app.sh"

# 가짜 앱: 실행되면 자기 이름을 출력한다
make_fake_apps() { # make_fake_apps <dir> <name>...
  local dir="$1" name; shift
  mkdir -p "$dir"
  for name in "$@"; do
    printf '#!/usr/bin/env bash\necho "RUNNING %s"\n' "$name" > "$dir/$name"
  done
}

echo "# app-arch.sh"
echo "## 아키텍처 → 바이너리 매핑"
# shellcheck source=/dev/null
source "$LIB"
assert_eq "agent-app-linux-x86"   "$(resolve_app_binary x86_64)"  "x86_64 → x86 (인텔)"
assert_eq "agent-app-linux-x86"   "$(resolve_app_binary amd64)"   "amd64 → x86"
assert_eq "agent-app-linux-arm64" "$(resolve_app_binary aarch64)" "aarch64 → arm64 (실리콘)"
assert_eq "agent-app-linux-arm64" "$(resolve_app_binary arm64)"   "arm64 → arm64"
OUT="$(resolve_app_binary riscv64 2>&1)"; RC=$?
assert_eq 1 "$RC" "미지원 아키텍처는 실패"
assert_contains "$OUT" "riscv64" "오류 메시지에 아키텍처 표시"

echo "## 호스트 감지"
assert_eq "x86_64" "$(AGENT_ARCH=x86_64 detect_host_arch)" "AGENT_ARCH 로 감지값 덮어쓰기"
assert_eq "$(uname -m)" "$(unset AGENT_ARCH; detect_host_arch)" "기본은 uname -m"
assert_eq "agent-app-linux-arm64" "$(AGENT_ARCH=aarch64 resolve_app_binary)" "인자 없으면 호스트 감지값 사용"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "## run-app.sh (root 라서 건너뜀: root 실행 금지 가드)"
else
  echo "## run-app.sh"
  d="$(new_case_dir)"
  make_fake_apps "$d" agent-app-linux-x86 agent-app-linux-arm64
  OUT="$(AGENT_ENV_FILE=/nonexistent AGENT_HOME="$d" AGENT_ARCH=x86_64 bash "$RUN" 2>&1)"; RC=$?
  assert_eq 0 "$RC" "x86_64 호스트에서 실행 성공"
  assert_contains "$OUT" "RUNNING agent-app-linux-x86" "x86_64 호스트는 인텔 버전 실행"
  OUT="$(AGENT_ENV_FILE=/nonexistent AGENT_HOME="$d" AGENT_ARCH=aarch64 bash "$RUN" 2>&1)"
  assert_contains "$OUT" "RUNNING agent-app-linux-arm64" "aarch64 호스트는 실리콘 버전 실행"
  assert_contains "$OUT" "aarch64" "감지한 아키텍처를 출력"

  d="$(new_case_dir)"
  make_fake_apps "$d" agent-app-linux-x86
  OUT="$(AGENT_ENV_FILE=/nonexistent AGENT_HOME="$d" AGENT_ARCH=aarch64 bash "$RUN" 2>&1)"; RC=$?
  assert_eq 1 "$RC" "맞는 버전이 없으면 exit 1 (다른 버전으로 대체하지 않음)"
  assert_contains "$OUT" "agent-app-linux-arm64" "없는 파일 경로를 알려 줌"
  assert_not_contains "$OUT" "RUNNING" "다른 아키텍처 바이너리를 실행하지 않음"

  OUT="$(AGENT_ENV_FILE=/nonexistent AGENT_HOME="$d" AGENT_ARCH=mips bash "$RUN" 2>&1)"; RC=$?
  assert_eq 1 "$RC" "미지원 아키텍처면 exit 1"
fi

echo "## install-app.sh"
src="$(new_case_dir)"; dst="$(new_case_dir)"
make_fake_apps "$src" agent-app-linux-x86 agent-app-linux-arm64
OUT="$(APP_OWNER="$(id -un)" APP_GROUP="$(id -gn)" AGENT_HOME="$dst" AGENT_ARCH=aarch64 bash "$INSTALL" "$src" 2>&1)"; RC=$?
assert_eq 0 "$RC" "설치 성공"
assert_file_exists "$dst/agent-app-linux-arm64" "호스트에 맞는 버전만 배치"
assert_file_missing "$dst/agent-app-linux-x86" "다른 버전은 배치하지 않음"
[[ -x "$dst/agent-app-linux-arm64" ]] && _ok "실행 권한 부여" || _fail "실행 권한 부여"
OUT="$(APP_OWNER="$(id -un)" APP_GROUP="$(id -gn)" AGENT_HOME="$dst" AGENT_ARCH=x86_64 bash "$INSTALL" "$dst/nope" 2>&1)"; RC=$?
assert_eq 1 "$RC" "원본이 없으면 exit 1"
assert_contains "$OUT" "agent-app-linux-x86" "찾던 파일을 알려 줌"

summary
