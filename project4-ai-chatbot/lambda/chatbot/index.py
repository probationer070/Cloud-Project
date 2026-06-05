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
import traceback
import uuid
import urllib.request
import boto3
from datetime import datetime, timezone

# ── 환경변수 ──────────────────────────────────────────
AI_PROVIDER           = os.environ.get("AI_PROVIDER", "gemini")   # "gemini" | "bedrock"
GEMINI_API_KEY_PATH   = os.environ.get("GEMINI_API_KEY_PATH", "/cloud-portfolio/gemini-api-key")
GEMINI_MODEL          = os.environ.get("GEMINI_MODEL", "gemini-2.0-flash")
BEDROCK_MODEL_ID      = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
DYNAMODB_TABLE        = os.environ["DYNAMODB_TABLE"]
SNS_TOPIC_ARN         = os.environ["SNS_TOPIC_ARN"]
COMPANY_NAME          = os.environ.get("COMPANY_NAME", "고객센터")
MAX_HISTORY_TURNS     = int(os.environ.get("MAX_HISTORY_TURNS", "10"))

dynamodb = boto3.resource("dynamodb")
sns      = boto3.client("sns")
ssm      = boto3.client("ssm")
_bedrock = None  # lazy-initialized only when AI_PROVIDER=bedrock
_gemini_api_key = None  # cached at cold start, fetched from SSM

table = dynamodb.Table(DYNAMODB_TABLE)


def get_gemini_api_key() -> str:
    global _gemini_api_key
    if _gemini_api_key is None:
        resp = ssm.get_parameter(Name=GEMINI_API_KEY_PATH, WithDecryption=True)
        _gemini_api_key = resp["Parameter"]["Value"]
    return _gemini_api_key

# ── System Prompt ─────────────────────────────────────
SYSTEM_PROMPT = f"""You are a friendly and professional customer service representative for {COMPANY_NAME}.

[Response Rules]
- Always maintain a polite and professional tone
- If you don't know the answer, honestly say so and offer to follow up
- Keep responses concise — 2 to 3 sentences
- If a customer uses offensive language, politely ask them to refrain

[Escalation Conditions] — You MUST include the keyword "ESCALATE" at the end of your response in these situations:
- The customer requests to speak with a human agent or representative
- The same issue has been repeated 3 or more times
- The customer mentions a refund dispute, legal action, or expresses serious dissatisfaction

[Prohibited Actions]
- Do not compare with competitors
- Do not promise arbitrary discounts
- Do not request personal information"""

PROFANITY_KEYWORDS = ["badword1", "badword2"]  # expand for production

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
        return cors_response(400, {"error": "Invalid JSON format"})

    user_message = (body.get("message") or "").strip()
    session_id   = body.get("session_id") or str(uuid.uuid4())

    if not user_message:
        return cors_response(400, {"error": "Please enter a message"})

    if len(user_message) > 1000:
        return cors_response(400, {"error": "Message too long (maximum 1000 characters)"})

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
        print(traceback.format_exc())
        ai_response = "I'm sorry, a temporary error occurred. Please try again in a moment."

    # 3. 응답 검증 및 라우팅
    escalate      = "ESCALATE" in ai_response
    has_profanity = any(kw in user_message for kw in PROFANITY_KEYWORDS)

    if has_profanity:
        final_response = "To ensure a smooth conversation, please use respectful language."
        escalate       = False
    elif escalate:
        # ESCALATE 키워드 제거 후 상담원 연결 메시지 추가
        final_response = ai_response.replace("ESCALATE", "").strip()
        final_response += "\n\nYou have requested to speak with an agent. Please hold and a representative will be with you shortly."
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
    api_key = get_gemini_api_key().strip()

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
    print(f"[Gemini] model={GEMINI_MODEL!r} url={url}")
    req = urllib.request.Request(
        url,
        data    = payload,
        headers = {
            "Content-Type":   "application/json",
            "x-goog-api-key": api_key,
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
                "timestamp":  now.isoformat() + "_0",
                "role":       "user",
                "content":    user_msg,
                "ttl":        ttl,
            })
            batch.put_item(Item={
                "session_id": session_id,
                "timestamp":  now.isoformat() + "_1",
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
            Subject  = f"[{COMPANY_NAME}] Agent Connection Request",
            Message  = (
                f"A customer has requested to speak with an agent.\n\n"
                f"Session ID:    {session_id}\n"
                f"Last Message:  {last_message}\n"
                f"Time:          {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M')} UTC\n\n"
                f"Check the session history in DynamoDB."
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
