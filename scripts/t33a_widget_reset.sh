#!/data/data/com.termux/files/usr/bin/bash
# T33A 위젯 원샷 리셋 — 위젯이 깨졌을 때 Termux 안에서 한 번 실행.
# 사용법: bash /sdcard/Download/T33A_wrapper (또는 bash ~/.shortcuts/t33a_reset)
#
# 이 스크립트는 무엇을 하는가:
#   1. 멈춰있는 start.sh / termux-toast 프로세스 정리
#   2. ~/.shortcuts/T33A 파일을 정확한 wrapper 내용으로 재작성
#   3. /sdcard/Download/T33A_wrapper 원본도 최신으로 재작성
#   4. 위젯 리로드 broadcast (이름 캐시 새로고침)
#   5. 결과를 /sdcard/Download/t33a_reset_result.txt 에 출력

LOG=/sdcard/Download/t33a_reset_result.txt
echo "$(date): === widget reset ===" > "$LOG"

# 1. stuck 프로세스 정리
pkill -f t33a_start.sh 2>>"$LOG"
pkill -f 'termux-toast T33A' 2>>"$LOG"
echo "stuck processes killed" >> "$LOG"

# 2. /sdcard 원본 wrapper 재작성 (shell/Termux 둘 다 실행 가능한 경로)
cat > /sdcard/Download/T33A_wrapper << 'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
echo "$(date): widget invoked" >> /sdcard/Download/t33a_widget_debug.log
bash /data/local/tmp/t33a_start.sh 2>>/sdcard/Download/t33a_widget_debug.log
WRAPPER
echo "--- /sdcard/Download/T33A_wrapper rewritten ---" >> "$LOG"
ls -la /sdcard/Download/T33A_wrapper >> "$LOG"

# 3. ~/.shortcuts/T33A 재작성 (위젯이 실제로 실행하는 파일)
mkdir -p ~/.shortcuts
cat > ~/.shortcuts/T33A << 'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
echo "$(date): widget invoked" >> /sdcard/Download/t33a_widget_debug.log
bash /data/local/tmp/t33a_start.sh 2>>/sdcard/Download/t33a_widget_debug.log
WRAPPER
chmod +x ~/.shortcuts/T33A
echo "--- ~/.shortcuts/T33A rewritten ---" >> "$LOG"
ls -la ~/.shortcuts/T33A >> "$LOG"
echo "--- content ---" >> "$LOG"
cat ~/.shortcuts/T33A >> "$LOG"

# 4. Termux:Widget 리로드 broadcast
am broadcast -a com.termux.widget.RELOAD 2>>"$LOG"
echo "--- widget reload broadcast sent ---" >> "$LOG"

echo "$(date): === RESET DONE ===" >> "$LOG"
echo "리셋 완료. 이제 홈 화면에서 T33A 위젯 탭 → 1초 내 토스트 확인"
cat "$LOG"
