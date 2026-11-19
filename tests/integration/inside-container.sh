#!/usr/bin/env bash
# Ubuntu 22.04 컨테이너 안에서 전체 설정 → 제공 앱 아키텍처 선택 확인 → 앱(mock) 기동 → monitor/cron/증빙 수집까지 실행하는 E2E.
# (UFW 는 컨테이너에서 enable 불가 → [WARNING] 경로가 검증된다)
set -u
export DEBIAN_FRONTEND=noninteractive
REPO=/repo
cd "$REPO" || exit 1

echo "=== 0. 패키지"
apt-get update -qq >/dev/null
apt-get install -y -qq openssh-server ufw acl cron iproute2 python3 procps gzip >/dev/null
mkdir -p /run/sshd

echo "=== 1. 단위 테스트 (Linux)"
bash tests/run_all.sh || exit 1

echo "=== 2. setup 01~05"
bash scripts/setup/01-ssh-firewall.sh || exit 1
bash scripts/setup/02-users-groups-dirs.sh || exit 1
bash scripts/setup/03-env-keyfile.sh || exit 1
bash scripts/setup/04-install-scripts.sh || exit 1
bash scripts/setup/05-cron.sh || exit 1

echo "=== 3. 검증: sshd 유효 설정"
sshd -T | grep -Ei '^(port|permitrootlogin) '
[[ "$(sshd -T | awk '$1=="port"{print $2}')" == "20022" ]] || { echo "FAIL port"; exit 1; }
[[ "$(sshd -T | awk '$1=="permitrootlogin"{print $2}')" == "no" ]] || { echo "FAIL permitrootlogin"; exit 1; }
/usr/sbin/sshd && ss -tlnp | grep -q ':20022 ' && echo "sshd listening on 20022 OK" || { echo "FAIL sshd listen"; exit 1; }

echo "=== 4. 검증: 그룹 구성"
id -nG agent-admin | grep -q agent-core && id -nG agent-dev | grep -q agent-core && ! id -nG agent-test | grep -q agent-core \
  && id -nG agent-test | grep -q agent-common && echo "groups OK" || { echo "FAIL groups"; exit 1; }

echo "=== 5. 검증: 권한 실동작"
su - agent-test -c 'touch /home/agent-admin/agent-app/upload_files/t.txt' && echo "test->upload_files write OK" || { echo "FAIL upload write"; exit 1; }
su - agent-test -c 'cat /home/agent-admin/agent-app/api_keys/t_secret.key' 2>/dev/null && { echo "FAIL test could read key"; exit 1; } || echo "test->api_keys denied OK"
su - agent-test -c 'ls /var/log/agent-app' 2>/dev/null && { echo "FAIL test could list log"; exit 1; } || echo "test->log dir denied OK"
su - agent-dev -c 'cat /home/agent-admin/agent-app/api_keys/t_secret.key' | grep -q agent_api_key_test && echo "dev->api_keys read OK" || { echo "FAIL dev read key"; exit 1; }
su - agent-admin -c 'touch /var/log/agent-app/.w && rm /var/log/agent-app/.w' && echo "admin->log write OK" || { echo "FAIL admin log write"; exit 1; }
[[ "$(stat -c %G /home/agent-admin/agent-app/upload_files/t.txt)" == agent-common ]] && echo "setgid group inherit OK"

echo "=== 6. 앱 없는 상태에서 monitor.sh → exit 1"
su - agent-admin -c '. /etc/profile.d/agent-env.sh; /home/agent-admin/agent-app/bin/monitor.sh'; rc=$?
[[ $rc -eq 1 ]] && echo "exit 1 OK" || { echo "FAIL expected exit 1 got $rc"; exit 1; }

echo "=== 7. 제공 앱: 호스트 아키텍처($(uname -m))에 맞는 버전 배치·실행 (agent-app/ 가 있을 때만)"
if [[ -d "$REPO/agent-app" ]]; then
  bash scripts/setup/install-app.sh || { echo "FAIL install-app"; exit 1; }
  [[ "$(find /home/agent-admin/agent-app -maxdepth 1 -name 'agent-app-linux-*' | wc -l)" -eq 1 ]] || { echo "FAIL 한 버전만 배치돼야 한다"; exit 1; }
  # 맞는 아키텍처 바이너리라면 Boot Sequence 가 시작된다 (틀리면 Exec format error)
  su - agent-admin -c "timeout 5 bash $REPO/scripts/setup/run-app.sh" > /tmp/real-app.out 2>&1
  head -n 4 /tmp/real-app.out
  grep -q "Starting Agent Boot Sequence" /tmp/real-app.out && echo "arch-matched app exec OK" || { echo "FAIL real app exec"; exit 1; }
  pkill -f agent-app-linux 2>/dev/null; sleep 1
else
  echo "(agent-app/ 없음 → 건너뜀)"
fi

echo "=== 7-1. mock 앱 기동 (agent-admin)"
su - agent-admin -c "AGENT_USE_MOCK=1 nohup bash $REPO/scripts/setup/run-app.sh > /tmp/app.out 2>&1 &"
for _ in $(seq 1 10); do sleep 1; grep -q "Agent READY" /tmp/app.out && break; done
cat /tmp/app.out
grep -q "Agent READY" /tmp/app.out || { echo "FAIL app boot"; exit 1; }
ss -tlnp | grep ':15034 ' || { echo "FAIL app listen"; exit 1; }

echo "=== 8. monitor.sh 정상 실행"
su - agent-admin -c '. /etc/profile.d/agent-env.sh; /home/agent-admin/agent-app/bin/monitor.sh'; rc=$?
[[ $rc -eq 0 ]] && echo "exit 0 OK" || { echo "FAIL expected exit 0 got $rc"; exit 1; }
tail -n 2 /var/log/agent-app/monitor.log

echo "=== 9. cron 자동 누적 (최대 130초 대기)"
service cron start >/dev/null 2>&1 || true
before=$(wc -l < /var/log/agent-app/monitor.log)
for _ in $(seq 1 26); do sleep 5; after=$(wc -l < /var/log/agent-app/monitor.log); (( after > before )) && break; done
echo "before=$before after=$after"
(( after > before )) && echo "cron growth OK" || { echo "FAIL cron growth"; cat /var/log/agent-app/monitor.cron.log 2>/dev/null; exit 1; }

echo "=== 10. 보너스 스크립트"
su - agent-admin -c '. /etc/profile.d/agent-env.sh; /home/agent-admin/agent-app/bin/report.sh' || exit 1
su - agent-admin -c '. /etc/profile.d/agent-env.sh; /home/agent-admin/agent-app/bin/log_retention.sh --dry-run' || exit 1
su - agent-admin -c 'echo old > /var/log/agent-app/monitor.20260101_000000.log; touch -d "8 days ago" /var/log/agent-app/monitor.20260101_000000.log; . /etc/profile.d/agent-env.sh; /home/agent-admin/agent-app/bin/log_retention.sh' || exit 1
compgen -G '/var/log/monitor/agent-app/archive/monitor.20260101_000000.log.*.gz' >/dev/null && echo "retention archive OK" || { echo "FAIL retention"; exit 1; }
su - agent-test -c 'ls /var/log/monitor/agent-app/archive' 2>/dev/null && { echo "FAIL test could list archive"; exit 1; } || echo "test->archive denied OK"

echo "=== 11. 증빙 수집 (컨테이너 내부 /tmp/evidence)"
bash scripts/setup/collect-evidence.sh /tmp/evidence >/dev/null && ls /tmp/evidence && cat /tmp/evidence/12-monitor-run.txt
echo "=== E2E PASSED"
