PROJECT: t33a-remapper
TASK: 재부팅 후 데몬 부활 2회(`t33 remapper` mdns 재연결, 잠금해제 대기 후 자동 재시도로 성공). 진단 소득: PID 16628 연속 생존 실측 → "mdns 미탐지 ≠ 데몬 사망"(무선 디버깅만 일시 사망). 전역 세션앵커 수리(`t33` 별칭 = 이 레포 등재).
STATUS: 데몬 Running(PID 16628). 폰측·코드 무변경(문서만)
NEXT: 실사 죽음(삼성 kill 자연발생) 시 notify_remote_dead 자동발화 e2e 1건 확인 (8/12 이관분 유지)
BRANCH: main | LAST: 28e9438 [docs]: /end — 원격알림
