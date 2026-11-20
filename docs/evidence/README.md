# 증빙 파일

`sudo scripts/setup/collect-evidence.sh` 가 생성한다. 파일 번호는 `docs/guide/01-평가-대비-체크리스트.md` 와 `docs/수행-내역서.md` 의 참조 번호와 같다.

| 파일 | 내용 |
|---|---|
| 01-sshd-config.txt | sshd Port/PermitRootLogin (grep + `sshd -T`) |
| 02-sshd-listen.txt | `ss -tulnp` sshd 라인 |
| 03-firewall.txt | `ufw status verbose` |
| 03a-root-denied.txt | 호스트에서 원격 SSH 검증 (22 timeout / 20022 일반계정 성공 / root 거부) — 수동 캡처 |
| 04-users-groups.txt | `id` ×3, `getent group` |
| 05-directories.txt | `ls -ld` 디렉토리 권한 |
| 06-acl.txt | `getfacl` |
| 07-permission-test.txt | 계정별 접근 실동작 |
| 08-env.txt | 환경 변수 |
| 09-keyfile.txt | 키 파일 |
| 09a-app-boot.txt | 앱 Boot Sequence 5단계 [OK] + Agent READY — 수동 캡처 |
| 10-app-listen.txt | 앱 15034 LISTEN |
| 11-monitor-script.txt | monitor.sh 소유/권한 |
| 12-monitor-run.txt | monitor.sh 실행 결과 |
| 12a-monitor-fail.txt | 앱 종료 상태에서 monitor.sh [FAIL] — 수동 캡처 |
| 13-monitor-log.txt | monitor.log 최근 라인 |
| 14-crontab.txt | crontab(monitor 매분 + log_retention 매일 03:00) + syslog CRON |
| 15-cron-growth.txt | syslog CRON 실행 기록 + 65초 전후 로그 줄 수 |
| 16-report.txt | 보너스 1 |
| 17-log-retention.txt | 보너스 2 (dry-run) |

`sample-docker-e2e.txt` 는 Ubuntu 26.04 **컨테이너**(arm64)에서 돌린 E2E 결과로, 기대 출력의 참고용이다(UFW 는 컨테이너 제약으로 비활성). 제출용 증빙은 VM 에서 다시 수집한다.
