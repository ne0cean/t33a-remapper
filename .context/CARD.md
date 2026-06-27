PROJECT: t33a-remapper (T33A BLE 리모컨 → 말해보카 키 리매퍼)
TASK: 리셋 세션 복구 + "PC 연결만으로 즉시 복구" 대안(launchd t33a-auto-tcpip) 커밋 + 콜드패스 검증 마커
STATUS: 평상시 동작 정상(tcp:5555·status=active·relay_hb 1s). 콜드패스 풀체인만 미검증
NEXT: 다음 실제 재부팅 시 /tmp/t33a-tcpip.log 확인 → ✅복구확인 뜨면 Next Tasks #0 클로즈
BRANCH: main | LAST: 58f9426 docs: 콜드패스 풀체인 검증
