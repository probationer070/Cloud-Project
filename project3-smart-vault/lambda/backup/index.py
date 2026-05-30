"""
Backup Lambda
- EventBridge 스케줄러 트리거 (매시간 / 매일)
- backup:true 태그가 붙은 EC2 인스턴스 자동 감지
- EBS 볼륨 스냅샷 생성 (증분 백업)
- 스냅샷에 메타데이터 태그 자동 부여
- SNS로 백업 결과 리포트 발송
"""

import json
import os
import boto3
from datetime import datetime, timezone

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN    = os.environ["SNS_TOPIC_ARN"]
BACKUP_TAG_KEY   = os.environ.get("BACKUP_TAG_KEY", "backup")
BACKUP_TAG_VALUE = os.environ.get("BACKUP_TAG_VALUE", "true")
RETENTION_DAYS   = int(os.environ.get("RETENTION_DAYS", "7"))


def lambda_handler(event, context):
    now        = datetime.now(timezone.utc)
    schedule   = event.get("schedule", "hourly")   # EventBridge detail에서 전달
    results    = {"created": [], "skipped": [], "errors": []}

    print(f"[Backup] 시작 - schedule={schedule}, time={now.isoformat()}")

    # backup:true 태그가 붙은 EC2 인스턴스 조회
    instances = get_backup_targets()
    print(f"[Backup] 백업 대상 인스턴스: {len(instances)}개")

    for instance in instances:
        instance_id  = instance["InstanceId"]
        instance_name = get_tag(instance, "Name") or instance_id
        env           = get_tag(instance, "Environment") or "unknown"

        # 인스턴스에 연결된 EBS 볼륨 목록
        volumes = [
            bdm["Ebs"]["VolumeId"]
            for bdm in instance.get("BlockDeviceMappings", [])
            if "Ebs" in bdm
        ]

        for volume_id in volumes:
            try:
                snapshot = ec2.create_snapshot(
                    VolumeId    = volume_id,
                    Description = f"AutoBackup | {instance_name} | {now.strftime('%Y-%m-%dT%H:%M')}",
                    TagSpecifications=[{
                        "ResourceType": "snapshot",
                        "Tags": [
                            {"Key": "Name",           "Value": f"backup-{instance_name}-{now.strftime('%Y%m%d-%H%M')}"},
                            {"Key": "SourceInstance", "Value": instance_id},
                            {"Key": "SourceVolume",   "Value": volume_id},
                            {"Key": "Environment",    "Value": env},
                            {"Key": "BackupDate",     "Value": now.strftime("%Y-%m-%d")},
                            {"Key": "BackupTime",     "Value": now.strftime("%H:%M")},
                            {"Key": "Schedule",       "Value": schedule},
                            {"Key": "RetainUntil",    "Value": get_retain_until(now, RETENTION_DAYS)},
                            {"Key": "ManagedBy",      "Value": "smart-vault"},
                        ],
                    }],
                )
                snapshot_id = snapshot["SnapshotId"]
                results["created"].append({
                    "instance":    instance_name,
                    "volume":      volume_id,
                    "snapshot_id": snapshot_id,
                })
                print(f"[Backup] ✅ 스냅샷 생성: {snapshot_id} ({instance_name} / {volume_id})")

            except Exception as e:
                error_msg = str(e)
                results["errors"].append({
                    "instance": instance_name,
                    "volume":   volume_id,
                    "error":    error_msg,
                })
                print(f"[Backup] ❌ 오류: {instance_name}/{volume_id} → {error_msg}")

    # 결과 리포트 SNS 발송
    send_report(results, now, schedule)
    return {"statusCode": 200, "body": json.dumps(results)}


def get_backup_targets() -> list:
    """backup:true 태그가 있는 실행 중 인스턴스 반환"""
    response = ec2.describe_instances(
        Filters=[
            {"Name": f"tag:{BACKUP_TAG_KEY}", "Values": [BACKUP_TAG_VALUE]},
            {"Name": "instance-state-name",   "Values": ["running", "stopped"]},
        ]
    )
    instances = []
    for reservation in response["Reservations"]:
        instances.extend(reservation["Instances"])
    return instances


def get_tag(resource: dict, key: str) -> str | None:
    for tag in resource.get("Tags", []):
        if tag["Key"] == key:
            return tag["Value"]
    return None


def get_retain_until(now: datetime, days: int) -> str:
    from datetime import timedelta
    return (now + timedelta(days=days)).strftime("%Y-%m-%d")


def send_report(results: dict, now: datetime, schedule: str):
    created = results["created"]
    errors  = results["errors"]

    status  = "✅ 성공" if not errors else f"⚠️ 일부 실패 ({len(errors)}건)"

    lines = [
        f"[Smart Vault] 자동 백업 완료 — {status}",
        f"",
        f"실행 시각: {now.strftime('%Y-%m-%d %H:%M')} UTC",
        f"스케줄:    {schedule}",
        f"",
        f"── 생성된 스냅샷 ({len(created)}건) ──────────────",
    ]
    for item in created:
        lines.append(f"  • {item['instance']} / {item['volume']} → {item['snapshot_id']}")

    if errors:
        lines.append(f"")
        lines.append(f"── 실패 목록 ({len(errors)}건) ────────────────────")
        for item in errors:
            lines.append(f"  ✗ {item['instance']} / {item['volume']}: {item['error']}")

    sns.publish(
        TopicArn = SNS_TOPIC_ARN,
        Subject  = f"[Smart Vault] 백업 완료 | {now.strftime('%Y-%m-%d %H:%M')} | {status}",
        Message  = "\n".join(lines),
    )
