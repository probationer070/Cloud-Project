"""
Router Lambda
- S3 업로드 이벤트 및 API Gateway 요청 수신
- 파일 확장자/Content-Type 감지
- 정형(CSV/JSON) → SQS 정형 큐
- 비정형(PDF/이미지) → SQS 비정형 큐
- 알 수 없는 형식 → Quarantine 버킷
"""

import json
import os
import boto3
import urllib.parse
from datetime import datetime

s3 = boto3.client("s3")
sqs = boto3.client("sqs")

STRUCTURED_QUEUE_URL   = os.environ["STRUCTURED_QUEUE_URL"]
UNSTRUCTURED_QUEUE_URL = os.environ["UNSTRUCTURED_QUEUE_URL"]
QUARANTINE_BUCKET      = os.environ["QUARANTINE_BUCKET"]

STRUCTURED_TYPES   = {".csv", ".json"}
UNSTRUCTURED_TYPES = {".pdf", ".jpg", ".jpeg", ".png", ".tiff"}


def lambda_handler(event, context):
    # 💡 [디버깅 로그] 들어온 이벤트 구조를 그대로 출력해서 확인 가능하게 설정
    print(f"[Router] Received event: {json.dumps(event)}")

    # 💡 1. API Gateway Proxy 연동 분기 처리 추가
    # API Gateway를 거쳐 들어오면 데이터가 event["body"] 안에 문자열형태로 담겨 있습니다.
    if "body" in event:
        print("[Router] API Gateway를 통한 요청 감지 - Body 데이터 파싱")
        if isinstance(event["body"], str):
            event = json.loads(event["body"])
        else:
            event = event["body"]

    # 💡 2. 데이터 유효성 검증 (Records가 아예 없는 잘못된 요청 방어)
    if "Records" not in event:
        print("[Router] ❌ 에러: 이벤트 내에 'Records' 데이터가 존재하지 않습니다.")
        return {
            "statusCode": 400,
            "body": json.dumps({"message": "Invalid request format. 'Records' required."})
        }

    # 기존 메인 비즈니스 로직 실행
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key    = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        size   = record["s3"]["object"].get("size", 0)

        ext = "." + key.rsplit(".", 1)[-1].lower() if "." in key else ""

        print(f"[Router] bucket={bucket} key={key} ext={ext} size={size}")

        message = {
            "bucket": bucket,
            "key":    key,
            "size":   size,
            "received_at": datetime.utcnow().isoformat(),
        }

        if ext in STRUCTURED_TYPES:
            sqs.send_message(
                QueueUrl    = STRUCTURED_QUEUE_URL,
                MessageBody = json.dumps(message),
            )
            print(f"[Router] → 정형 큐 전달: {key}")

        elif ext in UNSTRUCTURED_TYPES:
            sqs.send_message(
                QueueUrl    = UNSTRUCTURED_QUEUE_URL,
                MessageBody = json.dumps(message),
            )
            print(f"[Router] → 비정형 큐 전달: {key}")

        else:
            # 알 수 없는 형식 → Quarantine
            dest_key = f"unknown/{datetime.utcnow().strftime('%Y/%m/%d')}/{key}"
            s3.copy_object(
                CopySource = {"Bucket": bucket, "Key": key},
                Bucket     = QUARANTINE_BUCKET,
                Key        = dest_key,
                Metadata   = {"reason": "unsupported_file_type", "original_key": key},
                MetadataDirective = "REPLACE",
            )
            s3.delete_object(Bucket=bucket, Key=key)
            print(f"[Router] → Quarantine 이동: {key}")

    # API Gateway 응답 포맷 준수 (CORS나 Proxy 대응을 위해 json.dumps 사용)
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps({"message": "routing complete"})
    }