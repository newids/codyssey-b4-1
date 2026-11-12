# codyssey-b4-1 — 컴퓨터가 알아서 자기 상태를 점검하게 만들기

Ubuntu 22.04 서버에 **SSH 포트 변경·Root 차단 → UFW 최소 허용 → 역할 기반 계정/그룹/ACL → 환경 변수 고정 → 제공 앱 실행 → monitor.sh 관제 → cron 매분 자동화 → 로그 보존** 을 구축하는 미션 제출물이다.

## 제출물

| # | 결과물 | 경로 |
|---|---|---|
| 1 | 요구사항 수행 내역서 | [`docs/수행-내역서.md`](docs/수행-내역서.md) (증빙 원본: `docs/evidence/`, 캡처: `docs/screenshots/`) |
| 2 | monitor.sh 소스코드 | [`scripts/monitor.sh`](scripts/monitor.sh) |
| 보너스 1 | report.sh | [`scripts/report.sh`](scripts/report.sh) |
| 보너스 2 | 로그 보존 정책 | [`scripts/log_retention.sh`](scripts/log_retention.sh) |

## 문서

| 문서 | 내용 |
|---|---|
| [`docs/guide/00-수행-가이드.md`](docs/guide/00-수행-가이드.md) | 단계별 절차(수동 명령 + 스크립트), 각 단계의 증빙 목록 |
| [`docs/guide/01-평가-대비-체크리스트.md`](docs/guide/01-평가-대비-체크리스트.md) | 요구사항 ↔ 증빙 파일 매핑 |
| [`docs/guide/02-보너스-가이드.md`](docs/guide/02-보너스-가이드.md) | report.sh, 로그 보존 정책, logrotate 대안 |
| [`docs/guide/03-트러블슈팅.md`](docs/guide/03-트러블슈팅.md) | 12가지 흔한 문제의 증상·원인·조치 |
| [`docs/qa/문제와-답변.md`](docs/qa/문제와-답변.md) | 과제 목표 6문항 + 심화·오개념·시나리오 Q&A |

## 빠른 실행 (Ubuntu 22.04, root)

```bash
sudo scripts/setup/01-ssh-firewall.sh        # SSH 20022, PermitRootLogin no, UFW 20022/15034
sudo scripts/setup/02-users-groups-dirs.sh   # 계정/그룹/디렉토리/ACL
sudo scripts/setup/03-env-keyfile.sh         # /etc/profile.d/agent-env.sh, t_secret.key
sudo scripts/setup/04-install-scripts.sh     # $AGENT_HOME/bin/{monitor,report,log_retention}.sh (agent-dev:agent-core 750)
# 제공 앱(agent-app.zip)을 $AGENT_HOME 에 풀고 agent-admin 으로 실행 (별도 터미널, Ctrl+C 로 종료)
sudo su - agent-admin -c 'bash ~/codyssey-b4-1/scripts/setup/run-app.sh'
sudo scripts/setup/05-cron.sh                # agent-admin crontab 매분
sudo scripts/setup/collect-evidence.sh       # docs/evidence/01~17-*.txt 생성 (약 70초)
```

## 테스트

```bash
bash tests/run_all.sh                    # 단위 테스트 (macOS/Linux, root 불필요)
bash tests/integration/docker-e2e.sh     # Ubuntu 22.04 컨테이너 E2E (설정→앱→monitor→cron→증빙)
```

## 저장소 구조

```
scripts/monitor.sh            제출 스크립트
scripts/report.sh             보너스 1
scripts/log_retention.sh      보너스 2
scripts/setup/                설정 자동화 (01~05), run-app.sh, collect-evidence.sh
scripts/mock/agent_app.py     제공 앱 없는 환경용 테스트 대역 (제출용 아님)
tests/                        단위 테스트 + Docker E2E
docs/                         미션 원문, 가이드, 수행 내역서, Q&A, 증빙
```
