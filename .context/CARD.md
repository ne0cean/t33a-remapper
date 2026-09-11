PROJECT: t33a-remapper
TASK: 맥 복구 데몬 v1(수동대기)→v4(능동+백오프) 전환. 15시간 방치 근본원인=맥이 폰을 기다리기만 함. 1차 review-pr + 2차 adversarial 지적 전량 반영, 장애주입 2회로 검증.
STATUS: 데몬 v4 가동(launchd, 단일 인스턴스 락). 폰 정상(remap 2프로세스·port 5555), 리모컨만 미연결(status=waiting)
NEXT: 리모컨 지참 시 실키 인터셉트 e2e 1회(5매핑 적용 확인)
BRANCH: main | LAST: 8467295 [fix]: 복구 데몬 v4
