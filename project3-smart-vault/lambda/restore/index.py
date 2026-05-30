"""
Restore Lambda
- API Gateway POST /restore 트리거 (수동 복구 요청)
- 지정한 스냅샷 ID 또는 인스턴스명 + 날짜로 복구
- 스냅샷 → 새 EBS 볼륨 생성
- 복구 결과 SNS 발송
"""

import json
import os
import boto3
from datetime import datetime, timezone

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
AWS_REGION    = os.environ.get("AWS_REGION", "ap-northeast-2")


def lambda_handler(event, context):
    # API Gateway REST API가 api_key_required = true로 설정되어
    # 유효한 API Key 없는 요청은 Lambda 호출 전에 Gateway에서 403 반환
    # API Gateway HTTP 이벤트 파싱
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return response(400, {"error": "요청 본문이 올바른 JSON이 아닙니다"})

    snapshot_id   = body.get("snapshot_id")
    instance_name = body.get("instance_name")
    backup_date   = body.get("backup_date")        # "2025-05-27" 형식
    volume_type   = body.get("volume_type", "gp3")
    availability_zone = body.get("availability_zone", f"{AWS_REGION}a")

    # snapshot_id 직접 지정 또는 인스턴스명+날짜로 검색
    if not snapshot_id:
        if not instance_name:
            return response(400, {"error": "snapshot_id 또는 instance_name 이 필요합니다"})
        snapshot_id = find_snapshot(instance_name, backup_date)
        if not snapshot_id:
            return response(404, {
                "error": f"스냅샷을 찾을 수 없습니다",
                "instance_name": instance_name,
                "backup_date":   backup_date,
            })

    # 스냅샷 정보 확인
    try:
        snap_info = ec2.describe_snapshots(SnapshotIds=[snapshot_id])["Snapshots"]
        if not snap_info:
            return response(404, {"error": f"스냅샷을 찾을 수 없습니다: {snapshot_id}"})
        snap = snap_info[0]
    except Exception as e:
        return response(500, {"error": f"스냅샷 조회 실패: {str(e)}"})

    # 스냅샷 → 새 EBS 볼륨 생성
    now  = datetime.now(timezone.utc)
    tags = [
        {"Key": "Name",          "Value": f"restored-{snapshot_id}-{now.strftime('%Y%m%d-%H%M')}"},
        {"Key": "RestoredFrom",  "Value": snapshot_id},
        {"Key": "RestoredAt",    "Value": now.isoformat()},
        {"Key": "ManagedBy",     "Value": "smart-vault"},
    ]

    try:
        vol = ec2.create_volume(
            SnapshotId        = snapshot_id,
            AvailabilityZone  = availability_zone,
            VolumeType        = volume_type,
            TagSpecifications = [{"ResourceType": "volume", "Tags": tags}],
        )
        volume_id = vol["VolumeId"]
        print(f"[Restore] ✅ 볼륨 생성: {volume_id} ← {snapshot_id}")

        # SNS 알림
        sns.publish(
            TopicArn = SNS_TOPIC_ARN,
            Subject  = f"[Smart Vault] 복구 완료: {volume_id}",
            Message  = (
                f"복구가 완료되었습니다.\n\n"
                f"스냅샷 ID:  {snapshot_id}\n"
                f"새 볼륨 ID: {volume_id}\n"
                f"볼륨 타입:  {volume_type}\n"
                f"가용 영역:  {availability_zone}\n"
                f"복구 시각:  {now.strftime('%Y-%m-%d %H:%M')} UTC\n\n"
                f"다음 단계:\n"
                f"  1. 새 볼륨을 EC2 인스턴스에 연결 (Attach Volume)\n"
                f"  2. 마운트 후 데이터 확인\n"
            ),
        )

        return response(200, {
            "message":            "복구 볼륨 생성 완료",
            "volume_id":          volume_id,
            "source_snapshot_id": snapshot_id,
            "availability_zone":  availability_zone,
            "volume_type":        volume_type,
            "restored_at":        now.isoformat(),
        })

    except Exception as e:
        print(f"[Restore] ❌ 볼륨 생성 실패: {e}")
        return response(500, {"error": f"볼륨 생성 실패: {str(e)}"})


def find_snapshot(instance_name: str, backup_date: str | None) -> str | None:
    """인스턴스 이름 + 날짜(옵션)로 가장 최근 스냅샷 검색"""
    filters = [
        {"Name": "tag:ManagedBy",      "Values": ["smart-vault"]},
        {"Name": "tag:SourceInstance", "Values": [instance_name]},
    ]
    if backup_date:
        filters.append({"Name": "tag:BackupDate", "Values": [backup_date]})

    snaps = ec2.describe_snapshots(
        OwnerIds = ["self"],
        Filters  = filters,
    ).get("Snapshots", [])

    if not snaps:
        return None

    # 가장 최근 스냅샷 반환
    snaps.sort(key=lambda s: s["StartTime"], reverse=True)
    return snaps[0]["SnapshotId"]


def response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers":    {"Content-Type": "application/json"},
        "body":       json.dumps(body, ensure_ascii=False),
    }
