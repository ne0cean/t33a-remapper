#!/usr/bin/env bash
# t33a-revive.sh — 컴퓨터 근처에서 T33A 리매퍼를 한 방에 되살린다.
#
# 배경(2026-08-12 진단): 루팅 없는 삼성폰에서 relay는 shell uid가 필요하고,
# 그 부트스트랩은 adbd-TCP loopback에 의존한다. 삼성이 주기적으로 죽인 뒤
# 컴퓨터 없이는 부활 불가 = "회사서 며칠 방치". 죽는 즉시 텔레그램 알림이 오면
# 이 스크립트로 컴퓨터 앞에서 즉시 복구한다(기존 무선디버깅 수동 토글 댄스 대체).
#
# 사용법:  bash scripts/t33a-revive.sh            # 기본 타깃
#          T33A_ADDR=192.168.0.18:5555 bash scripts/t33a-revive.sh
set -u
ADDR="${T33A_ADDR:-192.168.0.18:5555}"
a() { adb -s "$ADDR" "$@"; }

echo "── T33A revive → $ADDR"

# 1. 연결 (adbd가 5555 listen 중이어야 성공 — 아니면 폰서 무선디버깅 1회 토글 필요)
if ! adb connect "$ADDR" 2>&1 | grep -qiE "connected|already"; then
  echo "❌ adb connect 실패 — 폰 [개발자옵션 → 무선 디버깅] OFF→ON 1회 토글 후 재실행"
  exit 1
fi
sleep 1
a get-state >/dev/null 2>&1 || { echo "❌ device offline — 폰서 '이 컴퓨터 허용' 탭 후 재실행"; exit 1; }

# 2. 현재 상태
ST=$(a shell 'cat /data/local/tmp/t33a.status 2>/dev/null' | tr -d '\r')
HB=$(a shell 'echo $(( $(date +%s) - $(stat -c %Y /data/local/tmp/t33a.relay_hb 2>/dev/null || echo 0) ))' | tr -d '\r')
echo "   status=$ST  relay_hb_age=${HB}s"

# 3. relay 경유 재시작 (CLAUDE.md 규칙: 반드시 relay 경유 → PPID=1 standalone 생존)
echo "   relay 재기동..."
a shell "setsid /system/bin/sh /sdcard/Download/t33a_relay.sh < /dev/null > /dev/null 2>&1 &" 2>/dev/null

# 4. 검증 (최대 20s heartbeat 갱신 대기)
for i in $(seq 1 20); do
  sleep 1
  AGE=$(a shell 'echo $(( $(date +%s) - $(stat -c %Y /data/local/tmp/t33a.relay_hb 2>/dev/null || echo 0) ))' | tr -d '\r')
  ST=$(a shell 'cat /data/local/tmp/t33a.status 2>/dev/null' | tr -d '\r')
  if [ "${AGE:-999}" -lt 15 ]; then
    echo "✅ 복구됨 — status=$ST, relay_hb ${AGE}s, PID $(a shell 'cat /data/local/tmp/t33a_relay.pid' | tr -d '\r')"
    echo "   리모컨 버튼 눌러 실동작 확인 → 로그: adb -s $ADDR shell tail -5 /sdcard/Download/t33a.log"
    exit 0
  fi
done
echo "⚠️ heartbeat 미갱신 — 폰 로그 확인: adb -s $ADDR shell tail -20 /sdcard/Download/t33a_boot.log"
exit 1
