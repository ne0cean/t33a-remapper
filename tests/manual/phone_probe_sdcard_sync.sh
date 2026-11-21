#!/bin/bash
# phone_probe_sdcard_sync.sh — t33a_sync.sh 가 기대는 폰 사실 3가지를 실폰에서 확인하는 수동 탐침(맥에서 실행, adb 필요).
#   ① Termux uid 에 cmp·cp·mv 가 있다  ② /sdcard(FUSE)에서 임시 파일 → cmp → mv 교체가 된다
#   ③ shell uid 의 sh 가 실행 중인 /sdcard 스크립트를 Termux uid 가 mv 로 바꿔 끼워도, 실행 중인 sh 는 옛 내용을 끝까지 읽는다(relay 상황)
# Termux uid 실행은 a-team termux_ctrl 통로(/sdcard/Download/termux_ctrl.req → .resp)를 쓴다 — 통로가 바쁘면 중단.
# 건드리는 파일은 /sdcard/Download/.t33a_probe.* 뿐이고 끝나면 지운다. 사용: bash tests/manual/phone_probe_sdcard_sync.sh [adb 대상]
set -u
ADB="${ADB:-adb}"; DEV="${1:-}"
[ -n "$DEV" ] || DEV=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')
[ -n "$DEV" ] || { echo "폰 미연결"; exit 1; }
sh_() { "$ADB" -s "$DEV" shell "$@"; }
P=/sdcard/Download/.t33a_probe
[ -z "$(sh_ 'ls /sdcard/Download/termux_ctrl.req 2>/dev/null')" ] || { echo "termux_ctrl 통로 바쁨 — 중단"; exit 1; }

# shell uid 로 8초짜리 스크립트 실행 시작(옛 내용: 끝에 B-old)
sh_ "printf 'echo A > $P.out\nsleep 8\necho B-old >> $P.out\n' > $P.run.sh; rm -f $P.out; (setsid sh $P.run.sh < /dev/null > /dev/null 2>&1 &)"
sleep 2
# Termux uid 로 도구 확인 + 같은 폴더 임시 파일 → cmp → mv 로 실행 중인 스크립트 교체(새 내용: B-new)
ID="REQ_t33a_probe_$(date +%s)"
REQ=$(mktemp) && [ -n "$REQ" ] || exit 2
cat > "$REQ" <<EOF
$ID
echo "tools cmp=[\$(command -v cmp)] cp=[\$(command -v cp)] mv=[\$(command -v mv)] uid=\$(id -u)"
printf 'echo A > $P.out\nsleep 8\necho B-new >> $P.out\n' > $P.src
cp $P.src $P.run.sh.sync.\$\$ && cmp -s $P.src $P.run.sh.sync.\$\$ && mv -f $P.run.sh.sync.\$\$ $P.run.sh && echo "swap OK (tmp→cmp→mv on /sdcard)" || echo "swap FAIL"
EOF
sh_ "rm -f /sdcard/Download/termux_ctrl.resp"; "$ADB" -s "$DEV" push "$REQ" /sdcard/Download/termux_ctrl.req > /dev/null 2>&1; rm -f "$REQ"
R=""; for i in $(seq 1 20); do R=$(sh_ 'cat /sdcard/Download/termux_ctrl.resp 2>/dev/null'); case "$R" in "$ID"*) break ;; esac; R=""; sleep 1; done
[ -n "$R" ] && echo "$R" | sed 1d || echo "termux_ctrl 응답 없음(20초)"
sleep 9
OUT=$(sh_ "cat $P.out 2>/dev/null" | tr -d '\r' | tr '\n' ' ')
NOW=$(sh_ "tail -1 $P.run.sh" | tr -d '\r')
echo "실행 중이던 sh 의 출력: [$OUT]  /  교체 뒤 파일 끝 줄: [$NOW]"
sh_ "rm -f $P.run.sh $P.src $P.out $P.run.sh.sync.*"
case "$OUT" in "A B-old ") echo "판정: PASS — 실행 중 sh 는 옛 내용 유지, 파일은 새 내용";; *) echo "판정: FAIL"; exit 1;; esac
