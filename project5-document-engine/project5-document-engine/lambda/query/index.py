"""
Query Lambda — 의미 검색 + 답변 생성 (RAG 패턴)

실행 흐름:
  1. 사용자 질문 수신
  2. 질문을 Titan 임베딩으로 벡터화
  3. OpenSearch kNN 검색으로 유사 청크 top-k 추출
  4. 추출된 청크를 컨텍스트로 Bedrock Claude에 답변 요청
  5. 답변 + 출처 문서 반환
"""

import json
import os
import urllib.request
import urllib.parse
import hmac
import hashlib
import datetime
import boto3

# ── 환경변수 ──────────────────────────────────────────
OPENSEARCH_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"]
OPENSEARCH_INDEX    = os.environ.get("OPENSEARCH_INDEX", "documents")
BEDROCK_REGION      = os.environ.get("BEDROCK_REGION", "us-east-1")
BEDROCK_MODEL_ID    = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
AWS_REGION          = os.environ.get("AWS_REGION", "ap-northeast-2")
TOP_K               = int(os.environ.get("TOP_K", "5"))  # 검색 결과 상위 몇 개

bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)


def lambda_handler(event, context):
    # OPTIONS 처리 (CORS)
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return cors_response(200, {})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return cors_response(400, {"error": "올바른 JSON이 아닙니다"})

    question  = (body.get("question") or "").strip()
    top_k     = int(body.get("top_k", TOP_K))

    if not question:
        return cors_response(400, {"error": "question 필드가 필요합니다"})

    if len(question) > 500:
        return cors_response(400, {"error": "질문이 너무 깁니다 (최대 500자)"})

    print(f"[Query] 질문: {question[:80]}")

    try:
        # 1. 질문 벡터화
        query_vector = get_embedding(question)

        # 2. OpenSearch kNN 검색
        chunks = search_opensearch(query_vector, top_k)
        print(f"[Query] 검색 결과: {len(chunks)}개 청크")

        if not chunks:
            return cors_response(200, {
                "answer":  "관련 문서를 찾지 못했습니다. 문서를 먼저 업로드해주세요.",
                "sources": [],
                "chunks_used": 0,
            })

        # 3. Bedrock Claude로 답변 생성
        answer = generate_answer(question, chunks)

        # 4. 출처 정보 구성
        sources = list({c["source_key"] for c in chunks})  # 중복 제거

        return cors_response(200, {
            "answer":      answer,
            "sources":     sources,
            "chunks_used": len(chunks),
            "question":    question,
        })

    except Exception as e:
        print(f"[Query] ❌ 오류: {e}")
        return cors_response(500, {"error": f"처리 중 오류가 발생했습니다: {str(e)}"})


########################################################
# 1. Titan 임베딩
########################################################

def get_embedding(text: str) -> list[float]:
    body = json.dumps({
        "inputText":  text[:8000],
        "dimensions": 1536,
        "normalize":  True,
    })
    resp = bedrock.invoke_model(
        modelId     = "amazon.titan-embed-text-v2:0",
        body        = body,
        contentType = "application/json",
        accept      = "application/json",
    )
    return json.loads(resp["body"].read())["embedding"]


########################################################
# 2. OpenSearch kNN 검색
########################################################

def search_opensearch(vector: list, top_k: int) -> list[dict]:
    """벡터 유사도 기반 top-k 청크 검색"""
    query = {
        "size": top_k,
        "_source": ["doc_id", "source_key", "text", "chunk_index"],
        "query": {
            "knn": {
                "embedding": {
                    "vector": vector,
                    "k":      top_k,
                }
            }
        }
    }

    path    = f"/{OPENSEARCH_INDEX}/_search"
    payload = json.dumps(query).encode("utf-8")
    result  = _opensearch_request("POST", path, payload)

    hits = result.get("hits", {}).get("hits", [])
    return [
        {
            "text":       hit["_source"]["text"],
            "source_key": hit["_source"]["source_key"],
            "doc_id":     hit["_source"]["doc_id"],
            "score":      hit["_score"],
        }
        for hit in hits
    ]


########################################################
# 3. Bedrock Claude — 답변 생성 (RAG)
########################################################

def generate_answer(question: str, chunks: list[dict]) -> str:
    """
    RAG 패턴:
    검색된 청크들을 컨텍스트로 제공 → Claude가 그 안에서 답변 생성
    """
    # 컨텍스트 조합 (출처 표시 포함)
    context_parts = []
    for i, chunk in enumerate(chunks, 1):
        source = chunk["source_key"].split("/")[-1]  # 파일명만
        context_parts.append(f"[출처 {i}: {source}]\n{chunk['text']}")
    context = "\n\n---\n\n".join(context_parts)

    prompt = f"""당신은 문서 분석 전문가입니다. 아래 제공된 문서 내용만을 근거로 질문에 답변하세요.

[문서 내용]
{context}

[질문]
{question}

[답변 규칙]
- 반드시 위 문서 내용에 근거해서만 답변하세요
- 문서에 없는 내용은 "문서에서 확인할 수 없습니다"라고 하세요
- 답변 마지막에 참고한 출처를 명시하세요
- 간결하고 명확하게 답변하세요"""

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens":        1024,
        "messages": [{"role": "user", "content": prompt}],
    })

    resp   = bedrock.invoke_model(
        modelId     = BEDROCK_MODEL_ID,
        body        = body,
        contentType = "application/json",
        accept      = "application/json",
    )
    result = json.loads(resp["body"].read())
    return result["content"][0]["text"]


########################################################
# OpenSearch SigV4 서명 요청 헬퍼
########################################################

def _opensearch_request(method: str, path: str, payload: bytes = b""):
    session     = boto3.session.Session()
    credentials = session.get_credentials().get_frozen_credentials()

    host    = OPENSEARCH_ENDPOINT.replace("https://", "")
    service = "es"
    region  = AWS_REGION

    now        = datetime.datetime.utcnow()
    amz_date   = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")

    canonical_uri     = path
    canonical_headers = f"host:{host}\nx-amz-date:{amz_date}\n"
    signed_headers    = "host;x-amz-date"
    payload_hash      = hashlib.sha256(payload).hexdigest()
    canonical_request = "\n".join([
        method, canonical_uri, "",
        canonical_headers, signed_headers, payload_hash
    ])

    credential_scope = f"{date_stamp}/{region}/{service}/aws4_request"
    string_to_sign   = "\n".join([
        "AWS4-HMAC-SHA256", amz_date, credential_scope,
        hashlib.sha256(canonical_request.encode()).hexdigest()
    ])

    def sign(key, msg):
        return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()

    signing_key = sign(
        sign(sign(sign(
            f"AWS4{credentials.secret_key}".encode("utf-8"), date_stamp),
            region), service), "aws4_request"
    )
    signature = hmac.new(signing_key, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    auth = (
        f"AWS4-HMAC-SHA256 Credential={credentials.access_key}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )

    headers = {
        "Content-Type":  "application/json",
        "X-Amz-Date":    amz_date,
        "Authorization": auth,
    }
    if credentials.token:
        headers["X-Amz-Security-Token"] = credentials.token

    req = urllib.request.Request(
        f"https://{host}{path}",
        data    = payload if payload else None,
        headers = headers,
        method  = method,
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


########################################################
# CORS 응답 헬퍼
########################################################

def cors_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":                "application/json",
            "Access-Control-Allow-Origin":  "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }
