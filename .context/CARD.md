PROJECT: t33a-remapper
TASK: "리매퍼 미동작" 진단 → 실원인=재부팅 후 폰 BT off(리매퍼 무죄). boot.sh ensure_bluetooth_on() 3지점 배선 + /review HIGH(startup-skip) 폐쇄. e2e watchdog경로 PASS
STATUS: 코드·push 완료(f15fc3d·85782f6). 생재부팅 콜드패스+물리 키 인터셉트만 미검증(리모컨 부재)
NEXT: 리모컨+폰 물리접근 시 adb reboot→잠금해제→boot.log 'bluetooth re-enabled' 확인→리모컨 버튼→앱 반응 (10분 완결)
BRANCH: main | LAST: 2fb94a2 [docs]: /review HIGH 반영 기록
