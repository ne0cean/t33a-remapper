#!/bin/bash
# phone_probe_sdcard_sync.sh — t33a_sync.sh 가 기대는 폰 사실을 실폰에서 확인하는 수동 탐침(맥에서 실행, adb 필요).
#   ① Termux uid 에 cmp·cp·mv 가 있다  ② /sdcard(FUSE)에서 임시 파일 → cmp → mv 교체가 된다
#   ③ shell uid 의 sh 가 실행 중인 /sdcard 스크립트를 Termux uid 가 mv 로 바꿔 끼우면, 실행 중인 sh 는 옛 내용을 끝까지 읽는다(relay 상황)
#   (두 회차 모두 "교체 직후 출력=[A ]" 즉 sh 가 아직 sleep 중일 때 교체됐어야 판정이 유효하다)
#   ③' 대조군: 같은 상황에서 제자리 cp 로 덮으면 실행 중인 sh 가 새 내용(또는 깨진 내용)을 읽는다 — 이게 갈려야 ③이 의미가 있다
# 실행 스크립트는 약 200KB(주석 패딩)라 sh 가 한 번에 다 읽지 못한다: "echo A → sleep $HOLD(기본 30초) → 패딩 → 끝 줄 echo B-old".
# Termux uid 실행은 a-team termux_ctrl 통로(/sdcard/Download/termux_ctrl.req → .resp)를 쓴다 — 통로가 바쁘면 중단.
# 건드리는 파일은 /sdcard/Download/.t33a_probe.* 뿐이고 끝나면 지운다. 사용: bash tests/manual/phone_probe_sdcard_sync.sh [adb 대상]
set -u
ADB="${ADB:-adb}"; DEV="${1:-}"
[ -n "$DEV" ] || DEV=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')
[ -n "$DEV" ] || { echo "폰 미연결"; exit 1; }
sh_() { "$ADB" -s "$DEV" shell "$@"; }
# sh 가 잠든 시간 — termux_ctrl 통로 응답(수 초~십수 초)보다 길어야 교체가 sh 종료 전에 일어난다(8초로는 늦은 회차가 나왔다, 11-21 19:3x)
HOLD="${HOLD:-30}"
P=/sdcard/Download/.t33a_probe
# 같은 길이의 옛/새 스크립트를 폰에 만든다(패딩 4000줄 × 50B)
MK='mk() { { echo "echo A > '$P'.out"; echo "sleep '$HOLD'"; i=0; while [ $i -lt 4000 ]; do echo "# pad pad pad pad pad pad pad pad pad pad pad pad"; i=$((i+1)); done; echo "echo B-$1 >> '$P'.out"; } > $2; }'
sh_ "$MK; mk old $P.old; mk new $P.new; ls -l $P.old $P.new | awk '{print \$5, \$NF}'"

ctrl() {   # ctrl <명령...> — Termux uid 로 1회 실행하고 응답 본문 출력
  local ID="REQ_t33a_probe_$(date +%s)_$RANDOM" REQ R i
  [ -z "$(sh_ 'ls /sdcard/Download/termux_ctrl.req 2>/dev/null')" ] || { echo "termux_ctrl 통로 바쁨 — 중단"; exit 1; }
  REQ=$(mktemp) && [ -n "$REQ" ] || exit 2
  { echo "$ID"; printf '%s\n' "$@"; } > "$REQ"
  sh_ "rm -f /sdcard/Download/termux_ctrl.resp"; "$ADB" -s "$DEV" push "$REQ" /sdcard/Download/termux_ctrl.req > /dev/null 2>&1; rm -f "$REQ"
  for i in $(seq 1 20); do R=$(sh_ 'cat /sdcard/Download/termux_ctrl.resp 2>/dev/null'); case "$R" in "$ID"*) echo "$R" | sed 1d | grep -v '^rc=\|^duration=\|^--- '; return 0 ;; esac; sleep 1; done
  echo "termux_ctrl 응답 없음(20초)"; return 1
}

round() {   # round <mv|inplace> — 옛 스크립트를 shell uid 로 실행 시작 → 2초 뒤 Termux uid 가 새 내용으로 교체 → 결과 출력
  sh_ "cp $P.old $P.run.sh; rm -f $P.out; (setsid sh $P.run.sh < /dev/null > /dev/null 2>&1 &)"
  sleep 2
  if [ "$1" = mv ]; then
    ctrl "echo \"tools cmp=[\$(command -v cmp)] cp=[\$(command -v cp)] mv=[\$(command -v mv)] uid=\$(id -u)\"" \
         "cp $P.new $P.run.sh.sync.\$\$ && cmp -s $P.new $P.run.sh.sync.\$\$ && mv -f $P.run.sh.sync.\$\$ $P.run.sh && echo 'swap mv OK' || echo 'swap mv FAIL'"
  else
    ctrl "cp $P.new $P.run.sh && echo 'swap inplace OK' || echo 'swap inplace FAIL'"
  fi
  # 교체가 sh 가 끝나기 전에 일어났는지 — 이 시점 출력이 "A" 뿐이어야 한다(B 가 이미 있으면 늦은 교체라 판정 무효)
  echo "  $1: 교체 직후 출력=[$(sh_ "cat $P.out 2>/dev/null" | tr -d '\r' | tr '\n' ' ')]"
  sleep $((HOLD+3))
  echo "  $1: 실행 중이던 sh 의 출력=[$(sh_ "cat $P.out 2>/dev/null" | tr -d '\r' | tr '\n' ' ')] 교체 뒤 파일 끝 줄=[$(sh_ "tail -1 $P.run.sh" | tr -d '\r')]"
}
R1=$(round mv); echo "$R1"
R2=$(round inplace); echo "$R2"
sh_ "rm -f $P.old $P.new $P.run.sh $P.out $P.run.sh.sync.*"
ok1=0; ok2=0
case "$R1" in *"교체 직후 출력=[A ]"*"출력=[A B-old ]"*) ok1=1 ;; esac
case "$R2" in *"교체 직후 출력=[A ]"*) case "$R2" in *"실행 중이던 sh 의 출력=[A B-old ]"*) ;; *"실행 중이던 sh 의 출력=[A "*) ok2=1 ;; esac ;; esac
[ $ok1 = 1 ] && [ $ok2 = 1 ] && echo "판정: PASS — mv 교체는 실행 중 sh 를 보호하고, 제자리 cp 는 보호하지 못함(탐침이 둘을 가름)" && exit 0
echo "판정: FAIL (mv 보호=$ok1, 대조군 갈림=$ok2)"; exit 1
