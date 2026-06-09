########################################################
# Project 5: 지능형 문서 분석 엔진
# S3 + Textract + Bedrock Titan + OpenSearch + DynamoDB
# + Lambda(2) + API Gateway + CloudWatch
########################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

########################################################
# 1. S3 — 문서 저장 버킷
########################################################

resource "aws_s3_bucket" "documents" {
  bucket        = "${var.project_name}-docs-${var.suffix}"
  force_destroy = true
  tags          = merge(var.common_tags, { Role = "documents" })
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

########################################################
# 2. DynamoDB — 문서 메타데이터
########################################################

resource "aws_dynamodb_table" "documents" {
  name         = "${var.project_name}-documents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "doc_id"

  attribute {
    name = "doc_id"
    type = "S"
  }

  # source_key로 검색하는 GSI
  global_secondary_index {
    name            = "source-key-index"
    hash_key        = "source_key"
    projection_type = "ALL"
  }

  attribute {
    name = "source_key"
    type = "S"
  }

  tags = var.common_tags
}

########################################################
# 3. OpenSearch — 벡터 검색 엔진
# ⚠️ 비용 주의: 시간당 과금 → 테스트 후 즉시 destroy
########################################################

resource "aws_opensearch_domain" "engine" {
  domain_name    = "${var.project_name}-search"
  engine_version = "OpenSearch_2.11"

  # 최소 사양 (비용 최소화)
  cluster_config {
    instance_type  = "t3.small.search" # 가장 저렴한 옵션
    instance_count = 1                 # 단일 노드 (테스트용)
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10 # 10GB (최소)
    volume_type = "gp3"
  }

  # 노드 간 암호화
  encrypt_at_rest { enabled = true }
  node_to_node_encryption { enabled = true }

  # HTTPS 강제
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # IAM 기반 접근 제어 (Lambda IAM 역할만 허용)
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.ingest.arn,
            aws_iam_role.query.arn,
          ]
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-search/*"
      }
    ]
  })

  tags = var.common_tags
}

########################################################
# 4. OpenSearch 인덱스 생성 (배포 후 수동 실행)
# outputs의 create_index_command 참고
########################################################

# 인덱스 매핑은 terraform 외부에서 curl로 생성
# → outputs.tf의 create_index_command 참고

########################################################
# 5. SNS
########################################################

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = var.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

########################################################
# 6. Lambda 패키징
########################################################

resource "terraform_data" "install_ingest_deps" {
  triggers_replace = [filemd5("${path.module}/lambda/ingest/requirements.txt")]

  provisioner "local-exec" {
    command = "uv pip install -r ${path.module}/lambda/ingest/requirements.txt --target ${path.module}/lambda/ingest --quiet"
  }
}

data "archive_file" "ingest" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/ingest"
  output_path = "${path.module}/.terraform/lambda-ingest.zip"
  depends_on  = [terraform_data.install_ingest_deps]
}

data "archive_file" "query" {
  type        = "zip"
  source_file = "${path.module}/lambda/query/index.py"
  output_path = "${path.module}/.terraform/lambda-query.zip"
}

########################################################
# 7. Lambda 함수 2개
########################################################

# ── Ingest Lambda ──────────────────────────────────────
resource "aws_lambda_function" "ingest" {
  function_name    = "${var.project_name}-ingest"
  role             = aws_iam_role.ingest.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.ingest.output_path
  source_code_hash = data.archive_file.ingest.output_base64sha256
  timeout          = 300 # PDF 파싱 + 임베딩 생성이 오래 걸림
  memory_size      = 512

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = "https://${aws_opensearch_domain.engine.endpoint}"
      OPENSEARCH_INDEX    = var.opensearch_index
      DYNAMODB_TABLE      = aws_dynamodb_table.documents.name
      SNS_TOPIC_ARN       = aws_sns_topic.alerts.arn
      BEDROCK_REGION      = var.bedrock_region
      CHUNK_SIZE          = tostring(var.chunk_size)
      CHUNK_OVERLAP       = tostring(var.chunk_overlap)
    }
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 7
  tags              = var.common_tags
}

# S3 → Ingest Lambda 트리거
resource "aws_s3_bucket_notification" "documents" {
  bucket = aws_s3_bucket.documents.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest.arn
    events              = ["s3:ObjectCreated:*"]
    # PDF와 이미지만 트리거
    filter_suffix = ".pdf"
  }

  depends_on = [aws_lambda_permission.s3_invoke_ingest]
}

resource "aws_lambda_permission" "s3_invoke_ingest" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.documents.arn
}

# ── Query Lambda ───────────────────────────────────────
resource "aws_lambda_function" "query" {
  function_name    = "${var.project_name}-query"
  role             = aws_iam_role.query.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.query.output_path
  source_code_hash = data.archive_file.query.output_base64sha256
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = "https://${aws_opensearch_domain.engine.endpoint}"
      OPENSEARCH_INDEX    = var.opensearch_index
      BEDROCK_REGION      = var.bedrock_region
      BEDROCK_MODEL_ID    = var.bedrock_model_id
      TOP_K               = tostring(var.top_k)
    }
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "query" {
  name              = "/aws/lambda/${aws_lambda_function.query.function_name}"
  retention_in_days = 7
  tags              = var.common_tags
}

########################################################
# 8. API Gateway
########################################################

resource "aws_apigatewayv2_api" "engine" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }

  tags = var.common_tags
}

resource "aws_apigatewayv2_stage" "engine" {
  api_id      = aws_apigatewayv2_api.engine.id
  name        = "v1"
  auto_deploy = true
  tags        = var.common_tags
}

resource "aws_apigatewayv2_integration" "query" {
  api_id                 = aws_apigatewayv2_api.engine.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.query.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "query" {
  api_id    = aws_apigatewayv2_api.engine.id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.query.id}"
}

resource "aws_lambda_permission" "apigw_query" {
  statement_id  = "AllowAPIGatewayQuery"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.engine.execution_arn}/*/*"
}

########################################################
# 9. CloudWatch 알람 + 대시보드
########################################################

resource "aws_cloudwatch_metric_alarm" "ingest_errors" {
  alarm_name          = "${var.project_name}-ingest-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = aws_lambda_function.ingest.function_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_health" {
  alarm_name          = "${var.project_name}-opensearch-red"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "OpenSearch 클러스터 상태 RED"
  treat_missing_data  = "notBreaching"
  dimensions          = { DomainName = aws_opensearch_domain.engine.domain_name, ClientId = data.aws_caller_identity.current.account_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.common_tags
}

resource "aws_cloudwatch_dashboard" "engine" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title  = "Lambda 호출 (Ingest / Query)"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ingest.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.query.function_name],
          ]
          period = 300, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title  = "Lambda 처리 시간 (ms)"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.ingest.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.query.function_name],
          ]
          period = 300, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title  = "OpenSearch 검색 지연 시간"
          region = var.aws_region
          metrics = [
            ["AWS/ES", "SearchLatency", "DomainName", aws_opensearch_domain.engine.domain_name, "ClientId", data.aws_caller_identity.current.account_id]
          ]
          period = 300, stat = "Average", view = "timeSeries"
        }
      },
    ]
  })
}
