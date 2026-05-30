########################################################
# outputs.tf
########################################################

output "ingestion_bucket" {
  description = "파일 업로드할 S3 버킷 이름"
  value       = aws_s3_bucket.ingestion.id
}

output "processed_bucket" {
  description = "처리 결과 저장 버킷"
  value       = aws_s3_bucket.processed.id
}

output "quarantine_bucket" {
  description = "오류 파일 격리 버킷"
  value       = aws_s3_bucket.quarantine.id
}

output "api_endpoint" {
  description = "외부 데이터 수신 API 엔드포인트"
  value       = "${aws_apigatewayv2_stage.ingest.invoke_url}/upload"
}

output "dynamodb_table" {
  description = "처리 결과 DynamoDB 테이블"
  value       = aws_dynamodb_table.records.name
}

output "dashboard_url" {
  description = "CloudWatch 대시보드 URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.pipeline.dashboard_name}"
}

# ── 테스트용 명령어 모음 ───────────────────────────────

output "test_csv_upload" {
  description = "CSV 파일 테스트 업로드"
  value       = "aws s3 cp sample_data/test.csv s3://${aws_s3_bucket.ingestion.id}/test.csv"
}

output "test_pdf_upload" {
  description = "PDF 파일 테스트 업로드"
  value       = "aws s3 cp sample_data/test.pdf s3://${aws_s3_bucket.ingestion.id}/test.pdf"
}

output "test_unknown_upload" {
  description = "알 수 없는 형식 테스트 (Quarantine 동작 확인)"
  value       = "aws s3 cp sample_data/test.xyz s3://${aws_s3_bucket.ingestion.id}/test.xyz"
}

output "check_dynamodb" {
  description = "DynamoDB 저장 결과 확인"
  value       = "aws dynamodb scan --table-name ${aws_dynamodb_table.records.name} --region ${var.aws_region}"
}

output "check_quarantine" {
  description = "Quarantine 버킷 파일 확인"
  value       = "aws s3 ls s3://${aws_s3_bucket.quarantine.id}/ --recursive"
}
