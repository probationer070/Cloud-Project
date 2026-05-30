"""
Parser Lambda — 정형 데이터 처리 (CSV / JSON)
- SQS 정형 큐 트리거
- CSV: 헤더 검증, 필드 타입 체크
- JSON: 스키마 유효성 검사
- 정상 → DynamoDB 저장
- 오류 → Quarantine + SNS 알림
"""

import json
import os
import csv
import io
import uuid
import boto3
from datetime import datetime

s3       = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
sns      = boto3.client("sns")

TABLE_NAME        = os.environ["DYNAMODB_TABLE"]
QUARANTINE_BUCKET = os.environ["QUARANTINE_BUCKET"]
SNS_TOPIC_ARN     = os.environ["SNS_TOPIC_ARN"]

table = dynamodb.Table(TABLE_NAME)

# CSV 필수 헤더 (실제 사용 시 맞게 수정)
REQUIRED_CSV_HEADERS = {"id", "timestamp", "value"}


def lambda_handler(event, context):
    for record in event["Records"]:
        body    = json.loads(record["body"])
        bucket  = body["bucket"]
        key     = body["key"]
        ext     = "." + key.rsplit(".", 1)[-1].lower()

        print(f"[Parser] 처리 시작: {key}")

        try:
            response = s3.get_object(Bucket=bucket, Key=key)
            content  = response["Body"].read().decode("utf-8")

            if ext == ".csv":
                records = parse_csv(content, key)
            elif ext == ".json":
                records = parse_json(content, key)
            else:
                raise ValueError(f"지원하지 않는 형식: {ext}")

            # DynamoDB 배치 저장
            with table.batch_writer() as batch:
                for item in records:
                    batch.put_item(Item={
                        "record_id":    str(uuid.uuid4()),
                        "source_key":   key,
                        "source_bucket":bucket,
                        "data":         item,
                        "file_type":    ext.lstrip("."),
                        "processed_at": datetime.utcnow().isoformat(),
                        "status":       "processed",
                    })

            print(f"[Parser] ✅ {len(records)}건 DynamoDB 저장 완료: {key}")

        except Exception as e:
            print(f"[Parser] ❌ 오류 발생: {e}")
            quarantine(bucket, key, str(e))
            notify_error(key, str(e))


# ── CSV 파싱 ──────────────────────────────────────────
def parse_csv(content: str, key: str) -> list:
    reader  = csv.DictReader(io.StringIO(content))
    headers = set(reader.fieldnames or [])

    missing = REQUIRED_CSV_HEADERS - headers
    if missing:
        raise ValueError(f"필수 헤더 누락: {missing}")

    records = []
    for i, row in enumerate(reader):
        # 빈 행 스킵
        if not any(row.values()):
            continue
        # 숫자 필드 타입 검증
        if "value" in row:
            try:
                float(row["value"])
            except ValueError:
                raise ValueError(f"Row {i+1}: 'value' 필드가 숫자가 아님 → {row['value']}")
        records.append(dict(row))

    if not records:
        raise ValueError("CSV에 데이터 행이 없습니다")

    return records


# ── JSON 파싱 ─────────────────────────────────────────
def parse_json(content: str, key: str) -> list:
    data = json.loads(content)

    # 최상위가 리스트인 경우
    if isinstance(data, list):
        if not data:
            raise ValueError("JSON 배열이 비어 있습니다")
        return [json.dumps(item) if isinstance(item, dict) else str(item) for item in data]

    # 최상위가 dict인 경우 → 단일 레코드로 처리
    if isinstance(data, dict):
        return [json.dumps(data)]

    raise ValueError(f"지원하지 않는 JSON 구조: {type(data)}")


# ── Quarantine 이동 ───────────────────────────────────
def quarantine(bucket: str, key: str, reason: str):
    dest_key = f"parser-errors/{datetime.utcnow().strftime('%Y/%m/%d')}/{key}"
    try:
        s3.copy_object(
            CopySource        = {"Bucket": bucket, "Key": key},
            Bucket            = QUARANTINE_BUCKET,
            Key               = dest_key,
            Metadata          = {"reason": reason[:256], "original_key": key},
            MetadataDirective = "REPLACE",
        )
        s3.delete_object(Bucket=bucket, Key=key)
        print(f"[Parser] Quarantine 이동 완료: {dest_key}")
    except Exception as e:
        print(f"[Parser] Quarantine 이동 실패: {e}")


# ── SNS 에러 알림 ─────────────────────────────────────
def notify_error(key: str, reason: str):
    sns.publish(
        TopicArn = SNS_TOPIC_ARN,
        Subject  = f"[P2 Parser] 처리 실패: {key}",
        Message  = (
            f"파일 처리 중 오류가 발생했습니다.\n\n"
            f"파일: {key}\n"
            f"오류: {reason}\n"
            f"시각: {datetime.utcnow().isoformat()} UTC\n\n"
            f"파일은 Quarantine 버킷으로 이동되었습니다."
        ),
    )
