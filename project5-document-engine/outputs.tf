########################################################
# outputs.tf
########################################################

output "documents_bucket" {
  description = "문서 업로드할 S3 버킷"
  value       = aws_s3_bucket.documents.id
}

output "opensearch_endpoint" {
  description = "OpenSearch 엔드포인트"
  value       = "https://${aws_opensearch_domain.engine.endpoint}"
}

output "query_api_endpoint" {
  description = "질의응답 API 엔드포인트"
  value       = "${aws_apigatewayv2_stage.engine.invoke_url}/query"
}

output "dynamodb_table" {
  description = "문서 메타데이터 DynamoDB 테이블"
  value       = aws_dynamodb_table.documents.name
}

output "dashboard_url" {
  description = "CloudWatch 대시보드"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.engine.dashboard_name}"
}

########################################################
# Step-by-Step 테스트 명령어
########################################################

output "step1_create_index" {
  description = "【Step 1】 OpenSearch 인덱스 생성 (배포 후 최초 1회 실행)"
  value       = <<-EOT
    # OpenSearch가 완전히 준비되는 데 10~15분 소요
    # endpoint 값은 opensearch_endpoint output 확인 후 교체

    curl -X PUT "https://${aws_opensearch_domain.engine.endpoint}/${var.opensearch_index}" \
      --aws-sigv4 "aws:amz:${var.aws_region}:es" \
      --user "$(aws configure get aws_access_key_id):$(aws configure get aws_secret_access_key)" \
      -H "Content-Type: application/json" \
      -d '{
        "settings": {
          "index": {
            "knn": true,
            "knn.space_type": "cosinesimil"
          }
        },
        "mappings": {
          "properties": {
            "doc_id":       { "type": "keyword" },
            "source_key":   { "type": "keyword" },
            "chunk_index":  { "type": "integer" },
            "total_chunks": { "type": "integer" },
            "text":         { "type": "text", "analyzer": "standard" },
            "word_count":   { "type": "integer" },
            "indexed_at":   { "type": "date" },
            "embedding": {
              "type":      "knn_vector",
              "dimension": 1024,
              "method": {
                "name":       "hnsw",
                "space_type": "cosinesimil",
                "engine":     "nmslib"
              }
            }
          }
        }
      }'
  EOT
}

output "step2_upload_document" {
  description = "【Step 2】 PDF 문서 업로드 (Ingest Lambda 자동 트리거)"
  value       = <<-EOT
    # sample_docs/ 에 있는 테스트 PDF 업로드
    aws s3 cp sample_docs/sample.pdf s3://${aws_s3_bucket.documents.id}/sample.pdf

    # 처리 상태 모니터링 (Lambda 로그)
    aws logs tail /aws/lambda/${aws_lambda_function.ingest.function_name} \
      --follow --region ${var.aws_region}
  EOT
}

output "step3_check_metadata" {
  description = "【Step 3】 DynamoDB 처리 상태 확인"
  value       = "aws dynamodb scan --table-name ${aws_dynamodb_table.documents.name} --region ${var.aws_region}"
}

output "step4_check_index" {
  description = "【Step 4】 OpenSearch 색인 건수 확인"
  value       = <<-EOT
    curl -X GET "https://${aws_opensearch_domain.engine.endpoint}/${var.opensearch_index}/_count" \
      --aws-sigv4 "aws:amz:${var.aws_region}:es" \
      --user "$(aws configure get aws_access_key_id):$(aws configure get aws_secret_access_key)"
  EOT
}

output "step5_query_test" {
  description = "【Step 5】 의미 검색 + 답변 생성 테스트"
  value       = <<-EOT
    # 일반 질문
    curl -X POST ${aws_apigatewayv2_stage.engine.invoke_url}/query \
      -H "Content-Type: application/json" \
      -d '{"question": "이 문서의 핵심 내용은 무엇인가요?", "top_k": 3}'

    # 의미 검색 테스트 (표현이 달라도 같은 내용 검색)
    curl -X POST ${aws_apigatewayv2_stage.engine.invoke_url}/query \
      -H "Content-Type: application/json" \
      -d '{"question": "Q4 수익이 얼마인가요?", "top_k": 5}'
  EOT
}

output "destroy_warning" {
  description = "⚠️ 테스트 완료 후 즉시 실행 — OpenSearch 시간당 과금 차단"
  value       = <<-EOT
    # S3 버킷 비우기
    aws s3 rm s3://${aws_s3_bucket.documents.id} --recursive

    # 전체 리소스 삭제 (OpenSearch 삭제에 10~15분 소요)
    terraform destroy

    # ⚠️ OpenSearch는 삭제 확인까지 AWS 콘솔에서 반드시 확인!
    # https://${var.aws_region}.console.aws.amazon.com/esv3/home
  EOT
}
