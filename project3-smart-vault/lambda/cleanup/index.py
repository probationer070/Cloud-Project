"""
Cleanup Lambda
- EventBridge 스케줄러 트리거 (매일 새벽 2시)
- RetainUntil 태그 기준으로 만료된 스냅샷 자동 삭제
- 삭제 전 S3에 스냅샷 목록 아카이브 (감사 추적용)
- SNS로 정리 결과 리포트 발송
"""

import json
import os
import boto3

from datetime import datetime, timezone
from runner import run_cleanup
from policy import SnapshotPolicy

ec2 = boto3.client("ec2")
s3  = boto3.client("s3")
sns = boto3.client("sns")

SNS_TOPIC_ARN   = os.environ["SNS_TOPIC_ARN"]
ARCHIVE_BUCKET  = os.environ["ARCHIVE_BUCKET"]
# DRY_RUN: 실제 EC2 삭제 API 호출 여부
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"
# -------------------------
# Policy metrics
# -------------------------

def lambda_handler(event, context):
    now = datetime.now(timezone.utc)
    # SHADOW_MODE: 정책 평가만 수행 (runner 내부 영향)
    shadow_mode = os.getenv("SHADOW_MODE", "false").lower() == "true"
    
    policy_metrics = {
        "v1": {},
        "v2": {}
    }

    snapshots = get_managed_snapshots()

    result = run_cleanup(
        snapshots=snapshots,
        now=now,
        policy_metrics=policy_metrics,
        dry_run=DRY_RUN,
        shadow_mode=shadow_mode,
        ec2_client=ec2,
        policy_v1_cls=SnapshotPolicy,
        policy_v2_cls=SnapshotPolicy,
    )

    archive_results(result, now)
    send_report(result, now)

    return {
        "statusCode": 200,
        "body": json.dumps(result, default=str)
    }


# ---- Helper Functions ---

def get_managed_snapshots() -> list:
    """ "ManagedBy: smart-vault" 태그가 붙은 스냅샷만 조회"""
    paginator = ec2.get_paginator("describe_snapshots")

    snapshots = []
    for page in paginator.paginate(
        OwnerIds=["self"],
        Filters=[{"Name": "tag:ManagedBy", "Values": ["smart-vault"]}],
    ):
        snapshots.extend(page.get("Snapshots", []))

    return snapshots

def archive_results(results: dict, now: datetime):
    """삭제 결과를 S3에 JSON으로 저장 (감사 추적)"""
    key  = f"cleanup-logs/{now.strftime('%Y/%m/%d')}/cleanup-{now.strftime('%H%M%S')}.json"
    body = json.dumps({
        "executed_at": now.isoformat(),
        "dry_run":     DRY_RUN,
        "summary": {
            "deleted": len(results["deleted"]),
            "kept":    len(results["kept"]),
            "errors":  len(results["errors"]),
        },
        "details": results,
    }, ensure_ascii=False, indent=2)

    try:
        s3.put_object(
            Bucket      = ARCHIVE_BUCKET,
            Key         = key,
            Body        = body,
            ContentType = "application/json",
        )
        print(json.dumps({
            "level": "info",
            "msg": "archive_saved",
            "bucket": ARCHIVE_BUCKET,
            "key": key
        }))
    except Exception as e:
        print(f"[Cleanup] 아카이브 저장 실패: {e}")

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="[Smart Vault] ⚠️ 아카이브 실패",
            Message=f"cleanup archive 실패: {str(e)}"
        )


def send_report(results: dict, now: datetime):
    deleted = results.get("deleted", [])
    errors  = results.get("errors", [])
    kept    = results.get("kept", [])
    status  = "✅ 완료" if not errors else f"⚠️ 일부 오류 ({len(errors)}건)"

    lines = [
        f"[Smart Vault] 스냅샷 정리 완료 — {status}",
        f"",
        f"실행 시각: {now.strftime('%Y-%m-%d %H:%M')} UTC",
        f"DRY RUN:   {DRY_RUN}",
        f"",
        f"── 삭제된 스냅샷 ({len(deleted)}건) ──────────────",
    ]
    for item in deleted:
        lines.append(f"  🗑️  {item['id']} ({item['name']}) | 만료: {item['retain_until']}")

    lines += [
        f"",
        f"── 유지 중인 스냅샷 ({len(kept)}건) ─────────────",
    ]
    for item in kept:
        days = item.get("days_left", "?")
        lines.append(f"  ✅ {item['id']} | {days}일 남음")

    if errors:
        lines += [f"", f"── 오류 ({len(errors)}건) ───────────────────────"]
        for item in errors:
            lines.append(f"  ✗ {item['id']}: {item['error']}")

    message = "\n".join(lines)

    # SNS 256KB 제한 방어
    MAX_SIZE = 240 * 1024  # 여유 buffer

    if len(message.encode("utf-8")) > MAX_SIZE:
        message = message.encode("utf-8")[:MAX_SIZE].decode("utf-8", "ignore")
        message += "\n\n⚠️ 메시지가 너무 길어 일부 생략됨"
    
    sns.publish(
        TopicArn = SNS_TOPIC_ARN,
        Subject  = f"[Smart Vault] 스냅샷 정리 | {now.strftime('%Y-%m-%d')} | {status}",
        Message  = message,
    )
