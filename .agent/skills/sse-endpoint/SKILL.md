---
name: Implement SSE Endpoint
description: Server-Sent Events (SSE) 스트리밍 엔드포인트 생성 패턴
---

## 🌊 SSE 백엔드 라우터 구조 보일러플레이트

긴 시간이 걸리는 배치 작업, LLM 스트리밍 등을 위한 표준 SSE 응답 패턴입니다. 이 형태를 복사하여 목적에 맞게 수정하세요.

```python
import json
from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse

router = APIRouter()

def sse_event(event: str, data: dict) -> str:
    """SSE 포맷으로 이벤트 직렬화"""
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"

@router.post("/stream-task")
async def handle_stream_task(req: Request):
    
    async def stream_generator():
        try:
            # 1. 시작 신호
            yield sse_event("start", {"status": "작업이 시작되었습니다."})
            
            # 2. 메인 루프 (진행률 송출)
            for i in range(1, 101):
                if await req.is_disconnected():
                    # 클라이언트 쪽에서 창을 닫거나 요청을 강제 중단한 경우
                    break
                    
                # [TODO] 실제 작업 수행
                # await asyncio.sleep(0.1)
                
                yield sse_event("progress", {"current": i, "total": 100})
            
            # 3. 완료 신호
            yield sse_event("done", {"success": True, "result": "작업 마무으리"})
            
        except Exception as e:
            # 4. 에러 발생 시 HTTP 500이 아닌 SSE 이벤트로 우아하게 실패 전달
            yield sse_event("error", {"message": str(e)})
        finally:
            # 5. 최종 소켓 종료 목적의 신호
            yield sse_event("finished", {})

    return StreamingResponse(
        stream_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",  # Nginx 등 리버스 프록시 우회용 설정 
        },
    )
```

## 🚨 프론트엔드 연동 주의사항
1. 프론트엔드에서는 `EventSource` 또는 POST 지원을 위한 `fetch` 커스텀 스크립트(가칭 `useSSE` hook)를 사용해야 합니다.
2. 프론트엔드 상에서 `event === 'error'` 이벤트를 받으면 즉시 에러 알림 모달을 띄우고 상태를 초기화해야 합니다.
3. 스트림이 도중에 끊겼는지, 정상 완료 (`done`) 되었는지를 식별하기 위해 항상 `finished` 이벤트를 cleanup 플래그로 활용합니다.
