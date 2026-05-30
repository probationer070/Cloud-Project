########################################################
# outputs.tf
########################################################

output "archive_bucket" {
  description = "백업 로그 아카이브 버킷"
  value       = aws_s3_bucket.archive.id
}

output "dr_archive_bucket" {
  description = "재해 복구 버킷 (크로스 리전 복제 대상)"
  value       = aws_s3_bucket.dr_archive.id
}

output "restore_api_endpoint" {
  description = "수동 복구 API 엔드포인트"
  value       = "${aws_api_gateway_stage.vault.invoke_url}/restore"
}

output "restore_api_key_value" {
  description = "API Gateway가 생성한 복구 API 키 (curl 요청 시 x-api-key 헤더에 사용)"
  value       = aws_api_gateway_api_key.restore.value
  sensitive   = true
}

output "dashboard_url" {
  description = "CloudWatch 대시보드 URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.vault.dashboard_name}"
}

# ── 테스트 명령어 ──────────────────────────────────────

output "test_manual_backup" {
  description = "백업 Lambda 수동 실행 테스트"
  value       = <<-EOT
    aws lambda invoke \
      --function-name ${aws_lambda_function.backup.function_name} \
      --payload '{"schedule":"manual-test"}' \
      --region ${var.aws_region} \
      /tmp/backup-result.json && cat /tmp/backup-result.json
  EOT
}

output "test_manual_cleanup" {
  description = "정리 Lambda 수동 실행 (DRY_RUN=true 상태에서 안전하게 테스트)"
  value       = <<-EOT
    aws lambda invoke \
      --function-name ${aws_lambda_function.cleanup.function_name} \
      --region ${var.aws_region} \
      /tmp/cleanup-result.json && cat /tmp/cleanup-result.json
  EOT
}

output "test_restore_api" {
  description = "복구 API 테스트 (snapshot_id를 실제 값으로 교체, API Key는 terraform output -raw restore_api_key_value 로 확인)"
  value       = <<-EOT
    curl -X POST ${aws_api_gateway_stage.vault.invoke_url}/restore \
      -H "x-api-key: $(terraform output -raw restore_api_key_value)" \
      -H "Content-Type: application/json" \
      -d '{
        "snapshot_id": "snap-04318b66687e02625",
        "volume_type": "gp3",
        "availability_zone": "${var.aws_region}a"
      }'
  EOT
}

output "check_snapshots" {
  description = "생성된 스냅샷 목록 확인"
  value       = "aws ec2 describe-snapshots --owner-ids self --filters Name=tag:ManagedBy,Values=smart-vault --region ${var.aws_region} --query 'Snapshots[*].{ID:SnapshotId,Name:Tags[?Key==`Name`]|[0].Value,RetainUntil:Tags[?Key==`RetainUntil`]|[0].Value}' --output table"
}

output "check_archive_logs" {
  description = "S3 아카이브 로그 확인"
  value       = "aws s3 ls s3://${aws_s3_bucket.archive.id}/cleanup-logs/ --recursive"
}

output "check_dr_replication" {
  description = "DR 리전 복제 확인"
  value       = "aws s3 ls s3://${aws_s3_bucket.dr_archive.id}/ --recursive --region ${var.dr_region}"
}

output "add_backup_tag_example" {
  description = "EC2 인스턴스에 backup 태그 추가하는 방법"
  value       = "aws ec2 create-tags --resources i-xxxxxxxxxxxxxxxxx --tags Key=backup,Value=true --region ${var.aws_region}"
}
