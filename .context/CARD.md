PROJECT: t33a-remapper
TASK: 리모컨 지참 라이브 진단 — 리매퍼 SW 무죄(버튼 로그 실증), 실원인=삼성이 relay kill→adbd loopback 없인 부활불가(컴퓨터 없는 회사=며칠 방치). 루트리스 상시 adbd-TCP 물리적 불가 재확인(WADB Keeper=엉뚱레버). → 한계수용+폰→텔레그램 원격 다운/복구 알림 + t33a-revive.sh. review HIGH(전송전 state기록→kill시 3h침묵) 수리.
STATUS: 코드·push·폰 live 배포 완료(be2cc56). curl→telegram 200·상태머신 e2e PASS
NEXT: 실사 죽음(삼성 kill 자연발생) 시 notify_remote_dead 자동발화 e2e 1건 확인
BRANCH: main | LAST: be2cc56 [fix]: 원격알림 review HIGH — 전송 성공 후에만 state 기록
