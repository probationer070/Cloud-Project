########################################################
# Project 2: 복합 데이터 처리 서버리스 파이프라인
# S3 (3) + Lambda (3) + SQS (2) + DynamoDB + SNS + CloudWatch
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

########################################################
# 1. S3 버킷 3개
########################################################

# 공통 버킷 설정 모듈화
locals {
  bucket_names = {
    ingestion  = "${var.project_name}-ingestion-${var.suffix}"
    processed  = "${var.project_name}-processed-${var.suffix}"
    quarantine = "${var.project_name}-quarantine-${var.suffix}"
  }
}

# ── Ingestion 버킷 (데이터 유입) ──────────────────────
resource "aws_s3_bucket" "ingestion" {
  bucket        = local.bucket_names.ingestion
  force_destroy = true
  tags          = merge(var.common_tags, { Role = "ingestion" })
}

resource "aws_s3_bucket_public_access_block" "ingestion" {
  bucket                  = aws_s3_bucket.ingestion.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3로 암호화 (기본값)
resource "aws_s3_bucket_server_side_encryption_configuration" "ingestion" {
  bucket = aws_s3_bucket.ingestion.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# ── Processed 버킷 (처리 완료 결과) ──────────────────
resource "aws_s3_bucket" "processed" {
  bucket        = local.bucket_names.processed
  force_destroy = true
  tags          = merge(var.common_tags, { Role = "processed" })
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# 처리 결과 90일 후 자동 삭제 (비용 관리)
resource "aws_s3_bucket_lifecycle_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id
  rule {
    id     = "auto-delete-after-90-days"
    status = "Enabled"
    filter {
      prefix = "" # 모든 객체 대상
    }
    expiration { days = 90 }
  }
}

# ── Quarantine 버킷 (오류 파일 격리) ─────────────────
resource "aws_s3_bucket" "quarantine" {
  bucket        = local.bucket_names.quarantine
  force_destroy = true
  tags          = merge(var.common_tags, { Role = "quarantine" })
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket                  = aws_s3_bucket.quarantine.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

########################################################
# 2. SQS 큐 (정형 / 비정형)
########################################################

# ── 정형 데이터 큐 ─────────────────────────────────────
resource "aws_sqs_queue" "structured_dlq" {
  name                      = "${var.project_name}-structured-dlq"
  message_retention_seconds = 1209600 # 14일
  tags                      = var.common_tags
}

resource "aws_sqs_queue" "structured" {
  name                       = "${var.project_name}-structured-queue"
  visibility_timeout_seconds = 300   # Lambda 타임아웃과 동일
  message_retention_seconds  = 86400 # 1일
  tags                       = var.common_tags

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.structured_dlq.arn
    maxReceiveCount     = 3 # 3번 실패 시 DLQ로 이동
  })
}

# ── 비정형 데이터 큐 ───────────────────────────────────
resource "aws_sqs_queue" "unstructured_dlq" {
  name                      = "${var.project_name}-unstructured-dlq"
  message_retention_seconds = 1209600
  tags                      = var.common_tags
}

resource "aws_sqs_queue" "unstructured" {
  name                       = "${var.project_name}-unstructured-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  tags                       = var.common_tags

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.unstructured_dlq.arn
    maxReceiveCount     = 3
  })
}

########################################################
# 3. DynamoDB 테이블
########################################################

resource "aws_dynamodb_table" "records" {
  name         = "${var.project_name}-records"
  billing_mode = "PAY_PER_REQUEST" # 사용량 기반 과금 (Free Tier 적합)
  hash_key     = "record_id"

  attribute {
    name = "record_id"
    type = "S"
  }

  # source_key로 검색 가능하도록 GSI 추가
  global_secondary_index {
    name            = "source-key-index"
    hash_key        = "source_key"
    projection_type = "ALL"
  }

  attribute {
    name = "source_key"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = var.common_tags
}

########################################################
# 4. SNS 알림
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
# 5. Lambda 함수 패키징
########################################################

data "archive_file" "router" {
  type        = "zip"
  source_file = "${path.module}/lambda/router/index.py"
  output_path = "${path.module}/.terraform/lambda-router.zip"
}

data "archive_file" "parser" {
  type        = "zip"
  source_file = "${path.module}/lambda/parser/index.py"
  output_path = "${path.module}/.terraform/lambda-parser.zip"
}

# pypdf 의존성을 디렉터리에 설치한 뒤 디렉터리 전체를 zip (P5 패턴 동일)
resource "terraform_data" "install_extractor_deps" {
  triggers_replace = [filemd5("${path.module}/lambda/extractor/requirements.txt")]
  provisioner "local-exec" {
    command = "uv pip install -r ${path.module}/lambda/extractor/requirements.txt --target ${path.module}/lambda/extractor --quiet"
  }
}

data "archive_file" "extractor" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/extractor"
  output_path = "${path.module}/.terraform/lambda-extractor.zip"
  depends_on  = [terraform_data.install_extractor_deps]
}

########################################################
# 6. Lambda 함수 3개
########################################################

# ── Router Lambda ──────────────────────────────────────
resource "aws_lambda_function" "router" {
  function_name    = "${var.project_name}-router"
  role             = aws_iam_role.router.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.router.output_path
  source_code_hash = data.archive_file.router.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      STRUCTURED_QUEUE_URL   = aws_sqs_queue.structured.url
      UNSTRUCTURED_QUEUE_URL = aws_sqs_queue.unstructured.url
      QUARANTINE_BUCKET      = aws_s3_bucket.quarantine.id
    }
  }

  tags = var.common_tags
}

# S3 → Router Lambda 트리거
resource "aws_s3_bucket_notification" "ingestion_trigger" {
  bucket = aws_s3_bucket.ingestion.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.router.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke_router]
}

resource "aws_lambda_permission" "s3_invoke_router" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.router.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.ingestion.arn
}

# ── Parser Lambda ──────────────────────────────────────
resource "aws_lambda_function" "parser" {
  function_name    = "${var.project_name}-parser"
  role             = aws_iam_role.parser.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.parser.output_path
  source_code_hash = data.archive_file.parser.output_base64sha256
  timeout          = 300
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE    = aws_dynamodb_table.records.name
      QUARANTINE_BUCKET = aws_s3_bucket.quarantine.id
      SNS_TOPIC_ARN     = aws_sns_topic.alerts.arn
    }
  }

  tags = var.common_tags
}

# SQS 정형 큐 → Parser Lambda 트리거
resource "aws_lambda_event_source_mapping" "sqs_to_parser" {
  event_source_arn = aws_sqs_queue.structured.arn
  function_name    = aws_lambda_function.parser.arn
  batch_size       = 10
}

# ── Extractor Lambda ───────────────────────────────────
resource "aws_lambda_function" "extractor" {
  function_name    = "${var.project_name}-extractor"
  role             = aws_iam_role.extractor.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.extractor.output_path
  source_code_hash = data.archive_file.extractor.output_base64sha256
  timeout          = 300
  memory_size      = 512 # pypdf 파싱 + Rekognition 응답 처리를 위해 넉넉하게

  environment {
    variables = {
      DYNAMODB_TABLE    = aws_dynamodb_table.records.name
      PROCESSED_BUCKET  = aws_s3_bucket.processed.id
      QUARANTINE_BUCKET = aws_s3_bucket.quarantine.id
      SNS_TOPIC_ARN     = aws_sns_topic.alerts.arn
    }
  }

  tags = var.common_tags
}

# SQS 비정형 큐 → Extractor Lambda 트리거
resource "aws_lambda_event_source_mapping" "sqs_to_extractor" {
  event_source_arn = aws_sqs_queue.unstructured.arn
  function_name    = aws_lambda_function.extractor.arn
  batch_size       = 5 # 비정형은 처리 시간이 길어 배치 작게 설정
}

########################################################
# 7. API Gateway (외부 데이터 수신 엔드포인트)
########################################################

resource "aws_apigatewayv2_api" "ingest" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "데이터 수신 엔드포인트"
  tags          = var.common_tags
}

resource "aws_apigatewayv2_stage" "ingest" {
  api_id      = aws_apigatewayv2_api.ingest.id
  name        = "v1"
  auto_deploy = true
  tags        = var.common_tags
}

# API Gateway → Router Lambda 연동
resource "aws_apigatewayv2_integration" "router" {
  api_id                 = aws_apigatewayv2_api.ingest.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.router.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload" {
  api_id    = aws_apigatewayv2_api.ingest.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.router.id}"
}

resource "aws_lambda_permission" "apigw_invoke_router" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.router.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.ingest.execution_arn}/*/*"
}

########################################################
# 8. CloudWatch 알람 + 대시보드
########################################################

# Lambda 에러 알람 (3개 함수 공통)
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = {
    router    = aws_lambda_function.router.function_name
    parser    = aws_lambda_function.parser.function_name
    extractor = aws_lambda_function.extractor.function_name
  }

  alarm_name          = "${var.project_name}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "${each.key} Lambda 5분간 에러 5건 초과"
  treat_missing_data  = "notBreaching"

  dimensions = { FunctionName = each.value }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.common_tags
}

# DLQ 메시지 적재 알람 (처리 3회 실패 감지)
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  for_each = {
    structured   = aws_sqs_queue.structured_dlq.name
    unstructured = aws_sqs_queue.unstructured_dlq.name
  }

  alarm_name          = "${var.project_name}-${each.key}-dlq"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "${each.key} DLQ에 메시지 적재 — 처리 실패 확인 필요"
  treat_missing_data  = "notBreaching"

  dimensions = { QueueName = each.value }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.common_tags
}

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title  = "Lambda 호출 수"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.router.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.parser.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.extractor.function_name],
          ]
          period = 300, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title  = "Lambda 에러 수"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.router.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.parser.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.extractor.function_name],
          ]
          period = 300, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title  = "SQS 큐 메시지 수"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.structured.name],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.unstructured.name],
          ]
          period = 60, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Lambda 실행 시간 (ms)"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.parser.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.extractor.function_name],
          ]
          period = 300, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "DLQ 적재 현황 (처리 실패)"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.structured_dlq.name],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.unstructured_dlq.name],
          ]
          period = 300, stat = "Sum", view = "timeSeries"
        }
      },
    ]
  })
}
