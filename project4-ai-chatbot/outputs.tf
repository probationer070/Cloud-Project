########################################################
# outputs.tf
########################################################

output "chat_api_endpoint" {
  description = "챗봇 REST API 엔드포인트"
  value       = "${aws_apigatewayv2_stage.chatbot.invoke_url}/chat"
}

output "chatbot_ui_url" {
  description = "웹 UI 접속 URL"
  value       = "https://${aws_cloudfront_distribution.ui.domain_name}"
}

output "dynamodb_table" {
  description = "대화 이력 DynamoDB 테이블"
  value       = aws_dynamodb_table.sessions.name
}

output "dashboard_url" {
  description = "CloudWatch 대시보드"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.chatbot.dashboard_name}"
}

output "ui_upload_command" {
  description = "웹 UI 파일 S3 업로드"
  value       = "aws s3 sync ./website/ s3://${aws_s3_bucket.ui.id}/ --delete"
}

output "cache_invalidation_command" {
  description = "CloudFront 캐시 무효화 (UI 업데이트 후 실행)"
  value       = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.ui.id} --paths '/*'"
}

# ── 테스트 명령어 ──────────────────────────────────────

output "test_chat_basic" {
  description = "기본 대화 테스트"
  value       = <<-EOT
    curl -X POST ${aws_apigatewayv2_stage.chatbot.invoke_url}/chat \
      -H "Content-Type: application/json" \
      -d '{"message": "안녕하세요, 반품은 어떻게 하나요?", "session_id": "test-001"}'
  EOT
}

output "test_chat_escalation" {
  description = "상담원 연결 트리거 테스트"
  value       = <<-EOT
    curl -X POST ${aws_apigatewayv2_stage.chatbot.invoke_url}/chat \
      -H "Content-Type: application/json" \
      -d '{"message": "상담원 연결해주세요", "session_id": "test-002"}'
  EOT
}

output "test_chat_history" {
  description = "대화 이력 연속성 테스트 (같은 session_id로 2번 연속 호출)"
  value       = <<-EOT
    # 1번째 메시지
    curl -X POST ${aws_apigatewayv2_stage.chatbot.invoke_url}/chat \
      -H "Content-Type: application/json" \
      -d '{"message": "제 주문번호는 12345입니다", "session_id": "test-003"}'

    # 2번째 메시지 (이전 대화 기억하는지 확인)
    curl -X POST ${aws_apigatewayv2_stage.chatbot.invoke_url}/chat \
      -H "Content-Type: application/json" \
      -d '{"message": "아까 말한 주문 배송 조회해주세요", "session_id": "test-003"}'
  EOT
}

output "check_session_history" {
  description = "DynamoDB 대화 이력 확인"
  value       = "aws dynamodb query --table-name ${aws_dynamodb_table.sessions.name} --key-condition-expression 'session_id = :sid' --expression-attribute-values '{\":sid\":{\"S\":\"test-003\"}}' --region ${var.aws_region}"
}

output "switch_to_bedrock" {
  description = "Bedrock으로 전환하는 방법"
  value       = <<-EOT
    # variables.tf에서 아래 값 변경 후 terraform apply:
    # ai_provider = "bedrock"
    # bedrock_region = "us-east-1"
    #
    # 또는 환경변수로 즉시 업데이트:
    aws lambda update-function-configuration \
      --function-name ${aws_lambda_function.chatbot.function_name} \
      --environment "Variables={AI_PROVIDER=bedrock,DYNAMODB_TABLE=${aws_dynamodb_table.sessions.name},SNS_TOPIC_ARN=${aws_sns_topic.alerts.arn},COMPANY_NAME=${var.company_name},BEDROCK_REGION=us-east-1}" \
      --region ${var.aws_region}
  EOT
}
