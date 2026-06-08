########################################################
# Project 4: 고객 서비스 AI 챗봇
# API Gateway + Lambda + DynamoDB + SNS + S3(UI) + CloudFront
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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

########################################################
# 1. DynamoDB — 대화 이력 저장
########################################################

resource "aws_dynamodb_table" "sessions" {
  name         = "${var.project_name}-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  range_key    = "timestamp"

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  # TTL: 24시간 후 자동 만료 (비용 관리)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = var.common_tags
}

########################################################
# 2. SNS — 상담원 연결 알림
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
# 3. Lambda — 챗봇 핵심 로직
########################################################

data "archive_file" "chatbot" {
  type        = "zip"
  source_file = "${path.module}/lambda/chatbot/index.py"
  output_path = "${path.module}/.terraform/lambda-chatbot.zip"
}

# Gemini API 키 — Terraform이 placeholder로 생성, 실제 키는 apply 후 CLI로 1회 주입
# (SecureString = KMS 암호화 / ignore_changes = 실제 키를 apply가 덮어쓰지 않음)
resource "aws_ssm_parameter" "gemini" {
  name        = "/cloud-portfolio/gemini-api-key"
  description = "Gemini API key for P4 chatbot — real value seeded via CLI after apply"
  type        = "SecureString"
  value       = "PLACEHOLDER"
  tags        = var.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_lambda_function" "chatbot" {
  function_name    = "${var.project_name}-chatbot"
  role             = aws_iam_role.chatbot.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.chatbot.output_path
  source_code_hash = data.archive_file.chatbot.output_base64sha256
  timeout          = 45
  memory_size      = 256
  architectures    = ["arm64"]

  environment {
    variables = {
      # ── AI 제공자 설정 ─────────────────────────────
      # "gemini" 또는 "bedrock" 으로 변경하면 즉시 전환
      AI_PROVIDER         = var.ai_provider
      GEMINI_API_KEY_PATH = aws_ssm_parameter.gemini.name
      GEMINI_MODEL        = var.gemini_model
      BEDROCK_MODEL_ID    = var.bedrock_model_id
      BEDROCK_REGION      = var.bedrock_region

      # ── 챗봇 설정 ──────────────────────────────────
      DYNAMODB_TABLE    = aws_dynamodb_table.sessions.name
      SNS_TOPIC_ARN     = aws_sns_topic.alerts.arn
      COMPANY_NAME      = var.company_name
      MAX_HISTORY_TURNS = "10"
      ALLOWED_ORIGIN    = "https://${aws_cloudfront_distribution.ui.domain_name}"
    }
  }

  tags = var.common_tags
}

# Lambda 응답 시간 로그 (CloudWatch Insights 활용)
resource "aws_cloudwatch_log_group" "chatbot" {
  name              = "/aws/lambda/${aws_lambda_function.chatbot.function_name}"
  retention_in_days = 7 # 테스트용 7일만 보관
  tags              = var.common_tags
}

########################################################
# 4. API Gateway — REST 엔드포인트
########################################################

resource "aws_apigatewayv2_api" "chatbot" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "AI 챗봇 API"

  # CORS 설정 (웹 UI에서 직접 호출 허용)
  cors_configuration {
    allow_origins = ["*"] # 실제 서비스 시 특정 도메인으로 제한
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }

  tags = var.common_tags
}

resource "aws_apigatewayv2_stage" "chatbot" {
  api_id      = aws_apigatewayv2_api.chatbot.id
  name        = "v1"
  auto_deploy = true

  # API 액세스 로그
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      sourceIp           = "$context.identity.sourceIp"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      routeKey           = "$context.routeKey"
      status             = "$context.status"
      responseLength     = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
    })
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 7
  tags              = var.common_tags
}

resource "aws_apigatewayv2_integration" "chatbot" {
  api_id                 = aws_apigatewayv2_api.chatbot.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.chatbot.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "chat" {
  api_id    = aws_apigatewayv2_api.chatbot.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.chatbot.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chatbot.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.chatbot.execution_arn}/*/*"
}

########################################################
# 5. S3 + CloudFront — 웹 UI 호스팅
#    P1 인프라가 있으면 재활용 가능
#    없으면 아래 블록으로 새로 생성
########################################################

resource "aws_s3_bucket" "ui" {
  bucket        = "${var.project_name}-ui-${var.suffix}"
  force_destroy = true
  tags          = merge(var.common_tags, { Role = "chatbot-ui" })
}

resource "aws_s3_bucket_public_access_block" "ui" {
  bucket                  = aws_s3_bucket.ui.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ui" {
  bucket = aws_s3_bucket.ui.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_cloudfront_origin_access_control" "ui" {
  name                              = "${var.project_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "ui" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.project_name} chatbot UI"

  origin {
    domain_name              = aws_s3_bucket.ui.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.ui.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.ui.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.ui.id}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 300 # 5분 캐시 (챗봇 UI는 자주 업데이트될 수 있음)
    max_ttl     = 3600
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  tags = var.common_tags
}

resource "aws_s3_bucket_policy" "ui" {
  bucket = aws_s3_bucket.ui.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFront"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.ui.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.ui.arn
        }
      }
    }]
  })
}

########################################################
# 6. CloudWatch 알람 + 대시보드
########################################################

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "챗봇 Lambda 5분간 에러 5건 초과"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = aws_lambda_function.chatbot.function_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.project_name}-slow-response"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 10000 # 10초 초과 시 알람
  alarm_description   = "챗봇 응답 시간이 10초를 초과했습니다"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = aws_lambda_function.chatbot.function_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.common_tags
}

resource "aws_cloudwatch_dashboard" "chatbot" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title   = "챗봇 호출 수 (대화 건수)"
          region  = var.aws_region
          metrics = [["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.chatbot.function_name]]
          period  = 300, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title   = "응답 시간 (ms)"
          region  = var.aws_region
          metrics = [["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.chatbot.function_name]]
          period  = 300, stat = "Average", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title   = "에러 수"
          region  = var.aws_region
          metrics = [["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.chatbot.function_name]]
          period  = 300, stat = "Sum", view = "timeSeries"
        }
      },
    ]
  })
}
