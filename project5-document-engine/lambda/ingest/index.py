"""
Ingest Lambda — 문서 처리 파이프라인

실행 흐름:
  1. S3 업로드 이벤트 수신
  2. Textract로 텍스트 추출 (PDF / 이미지)
  3. 텍스트를 청크로 분할 (500토큰 단위, 50토큰 오버랩)
  4. 각 청크를 Bedrock Titan으로 임베딩 벡터 생성
  5. OpenSearch에 벡터 + 원문 색인
  6. DynamoDB에 문서 메타데이터 저장
  7. 처리 결과 SNS 알림
"""

import io
import json
import os
import re
import uuid
import urllib.request
import urllib.parse
import hmac
import hashlib
import datetime
import boto3
import pypdf
from boto3.dynamodb.conditions import Key

# ── 환경변수 ──────────────────────────────────────────
OPENSEARCH_ENDPOINT = os.environ["OPENSEARCH_ENDPOINT"]   # https://xxx.es.amazonaws.com
OPENSEARCH_INDEX    = os.environ.get("OPENSEARCH_INDEX", "documents")
DYNAMODB_TABLE      = os.environ["DYNAMODB_TABLE"]
SNS_TOPIC_ARN       = os.environ["SNS_TOPIC_ARN"]
BEDROCK_REGION      = os.environ.get("BEDROCK_REGION", "us-east-1")
AWS_REGION          = os.environ.get("AWS_REGION", "us-east-1")

CHUNK_SIZE    = int(os.environ.get("CHUNK_SIZE", "500"))    # 청크 크기 (단어 수)
CHUNK_OVERLAP = int(os.environ.get("CHUNK_OVERLAP", "50"))  # 청크 오버랩

bedrock  = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)
dynamodb = boto3.resource("dynamodb")
sns      = boto3.client("sns")
s3       = boto3.client("s3")

table = dynamodb.Table(DYNAMODB_TABLE)


def lambda_handler(event, context):
    for record in event["Records"]:
        bucket  = record["s3"]["bucket"]["name"]
        key     = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        doc_id  = str(uuid.uuid4())

        print(f"[Ingest] 처리 시작: s3://{bucket}/{key} → doc_id={doc_id}")

        # DynamoDB에 처리 시작 상태 기록
        save_metadata(doc_id, bucket, key, "processing")

        try:
            # 1. Textract 텍스트 추출
            full_text = extract_text(bucket, key)
            print(f"[Ingest] 텍스트 추출 완료: {len(full_text)}자")

            # 2. 청크 분할
            chunks = split_into_chunks(full_text, CHUNK_SIZE, CHUNK_OVERLAP)
            print(f"[Ingest] 청크 분할 완료: {len(chunks)}개")

            # 3. 임베딩 생성 + OpenSearch 색인
            indexed = 0
            for i, chunk in enumerate(chunks):
                vector = get_embedding(chunk)
                index_to_opensearch(doc_id, key, chunk, vector, i, len(chunks))
                indexed += 1

            # 4. 메타데이터 업데이트
            save_metadata(doc_id, bucket, key, "completed",
                          chunk_count=len(chunks), char_count=len(full_text))

            print(f"[Ingest] ✅ 완료: {indexed}개 청크 색인")
            notify_success(key, doc_id, len(chunks))

        except Exception as e:
            print(f"[Ingest] ❌ 실패: {e}")
            save_metadata(doc_id, bucket, key, "failed", error=str(e))
            notify_error(key, str(e))

    return {"statusCode": 200}


########################################################
# 1. Textract 텍스트 추출
########################################################

def extract_text(bucket: str, key: str) -> str:
    """PDF에서 텍스트 추출 (pypdf 사용 — Textract 구독 불필요)"""
    obj = s3.get_object(Bucket=bucket, Key=key)
    pdf_bytes = obj["Body"].read()
    reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))
    pages = []
    for page in reader.pages:
        text = page.extract_text()
        if text:
            pages.append(text)
    return "\n".join(pages)


########################################################
# 2. 텍스트 청크 분할
########################################################

def split_into_chunks(text: str, chunk_size: int, overlap: int) -> list[str]:
    """
    단어 단위로 청크 분할
    - chunk_size: 청크당 단어 수
    - overlap: 앞 청크와 겹치는 단어 수 (문맥 연속성 유지)
    """
    words  = text.split()
    chunks = []
    start  = 0

    while start < len(words):
        end   = min(start + chunk_size, len(words))
        chunk = " ".join(words[start:end])
        if chunk.strip():
            chunks.append(chunk.strip())
        start += chunk_size - overlap

    return chunks


########################################################
# 3. Bedrock Titan 임베딩 생성
########################################################

def get_embedding(text: str) -> list[float]:
    """텍스트 → 1536차원 벡터 (Titan Embeddings V2)"""
    body = json.dumps({
        "inputText":  text[:8000],  # Titan V2 최대 입력 제한
        "dimensions": 1024,
        "normalize":  True,
    })
    resp = bedrock.invoke_model(
        modelId     = "amazon.titan-embed-text-v2:0",
        body        = body,
        contentType = "application/json",
        accept      = "application/json",
    )
    result = json.loads(resp["body"].read())
    return result["embedding"]


########################################################
# 4. OpenSearch 색인
########################################################

def index_to_opensearch(doc_id: str, source_key: str, chunk_text: str,
                         vector: list, chunk_index: int, total_chunks: int):
    """청크 + 벡터를 OpenSearch에 색인"""
    chunk_id = f"{doc_id}_chunk_{chunk_index}"
    doc = {
        "doc_id":       doc_id,
        "source_key":   source_key,
        "chunk_index":  chunk_index,
        "total_chunks": total_chunks,
        "text":         chunk_text,
        "embedding":    vector,         # knn_vector 필드
        "indexed_at":   datetime.datetime.utcnow().isoformat(),
        "word_count":   len(chunk_text.split()),
    }

    path    = f"/{OPENSEARCH_INDEX}/_doc/{chunk_id}"
    payload = json.dumps(doc).encode("utf-8")
    _opensearch_request("PUT", path, payload)


########################################################
# 5. DynamoDB 메타데이터
########################################################

def save_metadata(doc_id: str, bucket: str, key: str, status: str,
                  chunk_count: int = 0, char_count: int = 0, error: str = ""):
    item = {
        "doc_id":      doc_id,
        "source_key":  key,
        "bucket":      bucket,
        "status":      status,
        "chunk_count": chunk_count,
        "char_count":  char_count,
        "updated_at":  datetime.datetime.utcnow().isoformat(),
    }
    if error:
        item["error"] = error[:500]

    table.put_item(Item=item)


########################################################
# 6. SNS 알림
########################################################

def notify_success(key: str, doc_id: str, chunk_count: int):
    sns.publish(
        TopicArn = SNS_TOPIC_ARN,
        Subject  = f"[P5] 문서 색인 완료: {key.split('/')[-1]}",
        Message  = (
            f"문서 처리가 완료되었습니다.\n\n"
            f"파일:     {key}\n"
            f"문서 ID:  {doc_id}\n"
            f"청크 수:  {chunk_count}개\n"
            f"시각:     {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M')} UTC\n\n"
            f"이제 /query API로 이 문서에 질문할 수 있습니다."
        ),
    )


def notify_error(key: str, error: str):
    sns.publish(
        TopicArn = SNS_TOPIC_ARN,
        Subject  = f"[P5] 문서 처리 실패: {key.split('/')[-1]}",
        Message  = f"파일: {key}\n오류: {error}",
    )


########################################################
# OpenSearch SigV4 서명 요청 헬퍼
########################################################

def _opensearch_request(method: str, path: str, payload: bytes = b""):
    """AWS SigV4 서명을 포함한 OpenSearch HTTP 요청"""
    session     = boto3.session.Session()
    credentials = session.get_credentials().get_frozen_credentials()

    host    = OPENSEARCH_ENDPOINT.replace("https://", "")
    service = "es"
    region  = AWS_REGION

    now       = datetime.datetime.utcnow()
    amz_date  = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp= now.strftime("%Y%m%d")

    # 정규 요청 구성
    canonical_uri     = path
    canonical_headers = f"host:{host}\nx-amz-date:{amz_date}\n"
    signed_headers    = "host;x-amz-date"
    payload_hash      = hashlib.sha256(payload).hexdigest()
    canonical_request = "\n".join([
        method, canonical_uri, "",
        canonical_headers, signed_headers, payload_hash
    ])

    # 서명 생성
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
