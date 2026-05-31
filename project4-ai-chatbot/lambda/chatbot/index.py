"""
Chatbot Lambda — 고객 서비스 AI 챗봇 핵심 로직

실행 흐름:
  1. 대화 이력 조회 (DynamoDB)
  2. 프롬프트 조립 (System Prompt + 이력 + 현재 질문)
  3. AI 호출 (Gemini or Bedrock — 환경변수로 전환)
  4. 응답 검증 및 라우팅 (상담원 연결 / 욕설 감지 / fallback)
  5. 대화 이력 저장 (DynamoDB)
"""

import json
import os
import uuid
import urllib.request
import boto3
from datetime import datetime, timezone

# ── 환경변수 ──────────────────────────────────────────
AI_PROVIDER       = os.environ.get("AI_PROVIDER", "gemini")   # "gemini" | "bedrock"
GEMINI_API_KEY    = os.environ.get("GEMINI_API_KEY", "")
GEMINI_MODEL      = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash-lite-preview-06-17")
BEDROCK_MODEL_ID  = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
DYNAMODB_TABLE    = os.environ["DYNAMODB_TABLE"]
SNS_TOPIC_ARN     = os.environ["SNS_TOPIC_ARN"]
COMPANY_NAME      = os.environ.get("COMPANY_NAME", "고객센터")
MAX_HISTORY_TURNS = int(os.environ.get("MAX_HISTORY_TURNS", "10"))

dynamodb = boto3.resource("dynamodb")
sns      = boto3.client("sns")
_bedrock = None  # lazy-initialized only when AI_PROVIDER=bedrock

table = dynamodb.Table(DYNAMODB_TABLE)

# ── System Prompt ─────────────────────────────────────
SYSTEM_PROMPT = f"""당신은 {COMPANY_NAME}의 친절한 고객 서비스 담당자입니다.

[응대 규칙]
- 항상 친절하고 전문적인 톤을 유지하세요
- 모르는 내용은 솔직하게 모른다고 말하고 확인 후 안내하겠다고 하세요
- 답변은 간결하게 2~3문장으로 유지하세요
- 고객이 욕설이나 비방을 할 경우 정중하게 자제를 요청하세요

[상담원 연결 조건] — 아래 상황에서는 반드시 응답 마지막에 "ESCALATE" 키워드를 포함하세요
- 고객이 "상담원", "사람", "담당자" 연결을 요청할 때
- 문제가 3번 이상 반복될 때
- 환불, 법적 조치, 심각한 불만을 표현할 때

[금지 사항]
- 경쟁사 비교 발언 금지
- 가격 할인 임의 약속 금지
- 개인정보 요청 금지"""

# ── 욕설 키워드 (간단한 필터) ─────────────────────────
PROFANITY_KEYWORDS = ["욕설1", "욕설2"]  # 실제 서비스 시 확장

########################################################
# Lambda 핸들러
########################################################

def lambda_handler(event, context):
    # CORS preflight 처리
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return cors_response(200, {})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return cors_response(400, {"error": "올바른 JSON 형식이 아닙니다"})

    user_message = (body.get("message") or "").strip()
    session_id   = body.get("session_id") or str(uuid.uuid4())

    if not user_message:
        return cors_response(400, {"error": "메시지를 입력해주세요"})

    if len(user_message) > 1000:
        return cors_response(400, {"error": "메시지가 너무 깁니다 (최대 1000자)"})

    print(f"[Chatbot] session={session_id} provider={AI_PROVIDER} len={len(user_message)}")

    # 1. 대화 이력 조회
    history = get_history(session_id)

    # 2. AI 호출
    try:
        if AI_PROVIDER == "gemini":
            ai_response = call_gemini(user_message, history)
        else:
            ai_response = call_bedrock(user_message, history)
    except Exception as e:
        print(f"[Chatbot] AI 호출 실패: {e}")
        ai_response = f"죄송합니다. 일시적인 오류가 발생했습니다. 잠시 후 다시 시도해주세요."

    # 3. 응답 검증 및 라우팅
    escalate      = "ESCALATE" in ai_response
    has_profanity = any(kw in user_message for kw in PROFANITY_KEYWORDS)

    if has_profanity:
        final_response = "원활한 상담을 위해 정중한 언어를 사용해 주시기 바랍니다."
        escalate       = False
    elif escalate:
        # ESCALATE 키워드 제거 후 상담원 연결 메시지 추가
        final_response = ai_response.replace("ESCALATE", "").strip()
        final_response += "\n\n상담원 연결을 요청하셨습니다. 잠시만 기다려 주시면 담당자가 연결됩니다."
        notify_escalation(session_id, user_message)
    else:
        final_response = ai_response

    # 4. 대화 이력 저장
    save_history(session_id, user_message, final_response)

    return cors_response(200, {
        "session_id": session_id,
        "response":   final_response,
        "escalated":  escalate,
        "timestamp":  datetime.now(timezone.utc).isoformat(),
    })


########################################################
# AI 호출 — Gemini
########################################################

def call_gemini(user_message: str, history: list) -> str:
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY 환경변수가 설정되지 않았습니다")

    # 대화 이력을 Gemini contents 형식으로 변환
    contents = []
    for turn in history[-MAX_HISTORY_TURNS:]:
        contents.append({"role": "user",  "parts": [{"text": turn["user"]}]})
        contents.append({"role": "model", "parts": [{"text": turn["assistant"]}]})
    contents.append({"role": "user", "parts": [{"text": user_message}]})

    payload = json.dumps({
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": contents,
        "generationConfig": {
            "temperature":     0.7,
            "maxOutputTokens": 512,
        },
    }).encode("utf-8")

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models"
        f"/{GEMINI_MODEL}:generateContent"
    )
    req = urllib.request.Request(
        url,
        data    = payload,
        headers = {
            "Content-Type":   "application/json",
            "x-goog-api-key": GEMINI_API_KEY,  # key in header, not URL
        },
        method  = "POST",
    )
    with urllib.request.urlopen(req, timeout=25) as resp:
        result = json.loads(resp.read())

    return result["candidates"][0]["content"]["parts"][0]["text"]


########################################################
# AI 호출 — Bedrock (Claude)
########################################################

def _get_bedrock():
    global _bedrock
    if _bedrock is None:
        _bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("BEDROCK_REGION", "us-east-1"))
    return _bedrock


def call_bedrock(user_message: str, history: list) -> str:
    messages = []
    for turn in history[-MAX_HISTORY_TURNS:]:
        messages.append({"role": "user",      "content": turn["user"]})
        messages.append({"role": "assistant", "content": turn["assistant"]})
    messages.append({"role": "user", "content": user_message})

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens":        512,
        "system":            SYSTEM_PROMPT,
        "messages":          messages,
    })

    resp = _get_bedrock().invoke_model(
        modelId     = BEDROCK_MODEL_ID,
        body        = body,
        contentType = "application/json",
        accept      = "application/json",
    )
    result = json.loads(resp["body"].read())
    return result["content"][0]["text"]


########################################################
# DynamoDB 대화 이력
########################################################

def get_history(session_id: str) -> list:
    """세션의 대화 이력 조회 (최신순 → 시간순 정렬)"""
    try:
        resp = table.query(
            KeyConditionExpression = boto3.dynamodb.conditions.Key("session_id").eq(session_id),
            ScanIndexForward       = True,   # 시간 오름차순
            Limit                  = MAX_HISTORY_TURNS * 2,
        )
        items   = resp.get("Items", [])
        history = []
        # user/assistant 쌍으로 묶기
        i = 0
        while i + 1 < len(items):
            if items[i]["role"] == "user" and items[i+1]["role"] == "assistant":
                history.append({
                    "user":      items[i]["content"],
                    "assistant": items[i+1]["content"],
                })
                i += 2
            else:
                i += 1
        return history
    except Exception as e:
        print(f"[Chatbot] 이력 조회 실패: {e}")
        return []


def save_history(session_id: str, user_msg: str, assistant_msg: str):
    """사용자 메시지와 AI 응답을 각각 저장"""
    now = datetime.now(timezone.utc)
    ttl = int(now.timestamp()) + 86400  # 24시간 후 자동 만료

    try:
        with table.batch_writer() as batch:
            batch.put_item(Item={
                "session_id": session_id,
                "timestamp":  now.isoformat() + "_user",
                "role":       "user",
                "content":    user_msg,
                "ttl":        ttl,
            })
            batch.put_item(Item={
                "session_id": session_id,
                "timestamp":  now.isoformat() + "_assistant",
                "role":       "assistant",
                "content":    assistant_msg,
                "ttl":        ttl,
            })
    except Exception as e:
        print(f"[Chatbot] 이력 저장 실패: {e}")


########################################################
# 상담원 연결 알림
########################################################

def notify_escalation(session_id: str, last_message: str):
    try:
        sns.publish(
            TopicArn = SNS_TOPIC_ARN,
            Subject  = f"[{COMPANY_NAME}] 상담원 연결 요청",
            Message  = (
                f"고객이 상담원 연결을 요청했습니다.\n\n"
                f"세션 ID:    {session_id}\n"
                f"마지막 메시지: {last_message}\n"
                f"시각:       {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M')} UTC\n\n"
                f"DynamoDB에서 세션 이력을 확인하세요."
            ),
        )
    except Exception as e:
        print(f"[Chatbot] SNS 발송 실패: {e}")


########################################################
# CORS 응답 헬퍼
########################################################

ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "*")


def cors_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":                "application/json",
            "Access-Control-Allow-Origin":  ALLOWED_ORIGIN,
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }
