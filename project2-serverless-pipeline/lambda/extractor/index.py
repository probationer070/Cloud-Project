"""
Extractor Lambda — 비정형 데이터 처리 (안전성 보안 버전)
"""

import json
import os
import uuid
import io
import boto3
import pypdf
from datetime import datetime, timezone

s3           = boto3.client("s3")
rekognition  = boto3.client("rekognition")
dynamodb     = boto3.resource("dynamodb")
sns          = boto3.client("sns")

TABLE_NAME        = os.environ["DYNAMODB_TABLE"]
PROCESSED_BUCKET  = os.environ["PROCESSED_BUCKET"]
QUARANTINE_BUCKET = os.environ["QUARANTINE_BUCKET"]
SNS_TOPIC_ARN     = os.environ["SNS_TOPIC_ARN"]

table = dynamodb.Table(TABLE_NAME)
IMAGE_TYPES = {".jpg", ".jpeg", ".png", ".tiff"}

def lambda_handler(event, context):
    for record in event["Records"]:
        try:
            body   = json.loads(record["body"])
            bucket = body["bucket"]
            key    = body["key"]
            ext    = "." + key.rsplit(".", 1)[-1].lower()
        except Exception as parse_err:
            print(f"[Extractor] SQS Body 파싱 실패: {parse_err}")
            continue

        print(f"[Extractor] 비동기 처리 시작: {key}")

        try:
            if ext == ".pdf":
                result = extract_pdf(bucket, key)
            elif ext in IMAGE_TYPES:
                result = extract_image(bucket, key)
            else:
                raise ValueError(f"지원하지 않는 형식: {ext}")

            # 3.12 대응 표준 시간 포맷팅
            current_date = datetime.now(timezone.utc).strftime('%Y/%m/%d')
            result_key = f"results/{current_date}/{uuid.uuid4()}.json"
            
            # 추출 결과를 Processed 버킷에 저장
            s3.put_object(
                Bucket      = PROCESSED_BUCKET,
                Key         = result_key,
                Body        = json.dumps(result, ensure_ascii=False),
                ContentType = "application/json",
            )

            # DynamoDB에 메타데이터 저장
            table.put_item(Item={
                "record_id":     str(uuid.uuid4()),
                "source_key":    key,
                "source_bucket": bucket,
                "result_key":    result_key,
                "file_type":     ext.lstrip("."),
                "page_count":    result.get("page_count", 1),
                "word_count":    result.get("word_count", 0),
                "label_count":   result.get("label_count", 0),
                "processed_at":  datetime.now(timezone.utc).isoformat(),
                "status":        "processed",
            })

            print(f"[Extractor] ✅ 비동기 처리 완료: {key} → {result_key}")

        except Exception as e:
            print(f"[Extractor] ❌ 오류 발생: {e}")
            # 안전하게 격리 및 알림 처리
            quarantine(bucket, key, str(e))
            notify_error(key, str(e))

# ── PDF: pypdf 텍스트 추출 (Textract 대체 — 계정 레벨 구독 불가, ERR-003) ──
def extract_pdf(bucket: str, key: str) -> dict:
    print(f"[pypdf] {key} 파일 텍스트 추출 시작")
    obj = s3.get_object(Bucket=bucket, Key=key)
    pdf_bytes = obj["Body"].read()
    reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))

    pages = []
    for page in reader.pages:
        text = page.extract_text()
        if text:
            pages.append(text)

    full_text = "\n".join(pages)
    return {
        "type":       "pdf",
        "source_key": key,
        "text":       full_text,
        "word_count": len(full_text.split()),
        "page_count": len(reader.pages),
        "extracted_at": datetime.now(timezone.utc).isoformat(),
    }

# ── 이미지: Rekognition 레이블 감지 ──────────────────
def extract_image(bucket: str, key: str) -> dict:
    response = rekognition.detect_labels(
        Image      = {"S3Object": {"Bucket": bucket, "Name": key}},
        MaxLabels  = 20,
        MinConfidence = 70.0,
    )

    labels = [
        {
            "name":       label["Name"],
            "confidence": round(label["Confidence"], 2),
            "parents":    [p["Name"] for p in label.get("Parents", [])],
        }
        for label in response.get("Labels", [])
    ]

    return {
        "type":         "image",
        "source_key":   key,
        "labels":       labels,
        "label_count":  len(labels),
        "top_label":    labels[0]["name"] if labels else "unknown",
        "extracted_at": datetime.now(timezone.utc).isoformat(),
    }

# ── Quarantine 이동 (안전성 보강) ───────────────────────────────────
def quarantine(bucket: str, key: str, reason: str):
    current_date = datetime.now(timezone.utc).strftime('%Y/%m/%d')
    dest_key = f"extractor-errors/{current_date}/{key.split('/')[-1]}"
    try:
        # 파일이 원래 버킷에 실존하는지 먼저 예외 확인 후 복사 복사
        s3.copy_object(
            CopySource        = {"Bucket": bucket, "Key": key},
            Bucket            = QUARANTINE_BUCKET,
            Key               = dest_key,
            Metadata          = {"reason": reason[:256], "original_key": key},
            MetadataDirective = "REPLACE",
        )
        s3.delete_object(Bucket=bucket, Key=key)
        print(f"[Quarantine] 격리 이동 완료: {dest_key}")
    except s3.exceptions.ClientError as e:
        if e.response['Error']['Code'] == "404":
            print(f"[Quarantine] ⚠️ 경고: 원본 파일이 Ingestion 버킷에 존재하지 않습니다(이미 Router등에 의해 지워졌을 수 있음). 정보만 로깅합니다.")
        else:
            print(f"[Extractor] Quarantine 이동 실패: {e}")

# ── SNS 에러 알림 ─────────────────────────────────────
def notify_error(key: str, reason: str):
    try:
        sns.publish(
            TopicArn = SNS_TOPIC_ARN,
            Subject  = f"[P2 Extractor] 처리 실패: {key}",
            Message  = (
                f"비정형 파일 처리 중 오류가 발생했습니다.\n\n"
                f"파일: {key}\n"
                f"오류: {reason}\n"
                f"시각: {datetime.now(timezone.utc).isoformat()} UTC\n\n"
                f"파일 처리에 실패하여 격리 프로세스가 트리거되었습니다."
            ),
        )
    except Exception as sns_err:
        print(f"[SNS] 알림 발송 실패: {sns_err}")