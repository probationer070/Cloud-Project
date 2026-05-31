########################################################
# Project 3: 지능형 자동 백업 (Smart Vault)
# EventBridge + Lambda(3) + S3(archive) + SNS + CloudWatch
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

# 크로스 리전 복제 대상 (재해 복구용)
provider "aws" {
  alias  = "dr_region"
  region = var.dr_region
}

########################################################
# 1. S3 아카이브 버킷 (정리 로그 + 백업 목록 보관)
########################################################

resource "aws_s3_bucket" "archive" {
  bucket        = "${var.project_name}-archive-${var.suffix}"
  force_destroy = true # 테스트 편의를 위해 버킷 삭제 시 강제로 객체도 삭제
  tags          = merge(var.common_tags, { Role = "archive" })
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# 아카이브 로그 1년 후 자동 삭제 - Simple 버전
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    id     = "archive-logs-1year"
    status = "Enabled"
    filter {
      prefix = "cleanup-logs/"
    }
    expiration { days = 365 }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}


# 버전 관리 (로그 덮어쓰기 방지)
resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id
  versioning_configuration { status = "Enabled" }
}

########################################################
# 2. 크로스 리전 복제 버킷 (DR — 재해 복구)
########################################################

resource "aws_s3_bucket" "dr_archive" {
  provider      = aws.dr_region
  bucket        = "${var.project_name}-dr-archive-${var.suffix}"
  force_destroy = true
  tags          = merge(var.common_tags, { Role = "dr-archive" })
}

resource "aws_s3_bucket_public_access_block" "dr_archive" {
  provider                = aws.dr_region
  bucket                  = aws_s3_bucket.dr_archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "dr_archive" {
  provider = aws.dr_region
  bucket   = aws_s3_bucket.dr_archive.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dr_archive" {
  provider = aws.dr_region
  bucket   = aws_s3_bucket.dr_archive.id

  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "dr_archive" {
  provider = aws.dr_region
  bucket   = aws_s3_bucket.dr_archive.id
  rule {
    id     = "dr-cleanup"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 400 }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

# 크로스 리전 복제 IAM 역할
resource "aws_iam_role" "s3_replication" {
  name = "${var.project_name}-s3-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "s3.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "${var.project_name}-s3-replication-policy"
  role = aws_iam_role.s3_replication.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = aws_s3_bucket.archive.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
        Resource = "${aws_s3_bucket.archive.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = "${aws_s3_bucket.dr_archive.arn}/*"
      },
    ]
  })
}

# 크로스 리전 복제 설정
resource "aws_s3_bucket_replication_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "replicate-to-dr"
    status = "Enabled"
    filter {
      prefix = "cleanup-logs/"
    }
    delete_marker_replication {
      status = "Disabled"
    }
    destination {
      bucket        = aws_s3_bucket.dr_archive.arn
      storage_class = "STANDARD_IA" # 비용 절감: 자주 안 읽는 DR 데이터
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.archive,
    aws_s3_bucket_versioning.dr_archive,
  ]
}

########################################################
# 3. SNS 알림
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
# 4. Lambda 패키징 (수정 후)
########################################################

data "archive_file" "backup" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/backup" # 폴더 전체를 압축
  output_path = "${path.module}/.terraform/lambda-backup.zip"
}

data "archive_file" "cleanup" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/cleanup" # 폴더 전체를 압축
  output_path = "${path.module}/.terraform/lambda-cleanup.zip"
}

data "archive_file" "restore" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/restore" # 폴더 전체를 압축
  output_path = "${path.module}/.terraform/lambda-restore.zip"
}

########################################################
# 5. Lambda 함수 3개
########################################################

# ── Backup Lambda ──────────────────────────────────────
resource "aws_lambda_function" "backup" {
  function_name    = "${var.project_name}-backup"
  role             = aws_iam_role.backup.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  filename         = data.archive_file.backup.output_path
  source_code_hash = data.archive_file.backup.output_base64sha256
  timeout          = 300
  memory_size      = 128

  environment {
    variables = {
      SNS_TOPIC_ARN    = aws_sns_topic.alerts.arn
      BACKUP_TAG_KEY   = "backup"
      BACKUP_TAG_VALUE = "true"
      RETENTION_DAYS   = tostring(var.retention_days)
    }
  }

  tags = var.common_tags
}

# ── Cleanup Lambda ─────────────────────────────────────
resource "aws_lambda_function" "cleanup" {
  function_name    = "${var.project_name}-cleanup"
  role             = aws_iam_role.cleanup.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  filename         = data.archive_file.cleanup.output_path
  source_code_hash = data.archive_file.cleanup.output_base64sha256
  timeout          = 300
  memory_size      = 128

  environment {
    variables = {
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
      ARCHIVE_BUCKET = aws_s3_bucket.archive.id
      DRY_RUN        = tostring(var.cleanup_dry_run)
    }
  }

  tags = var.common_tags
}

# ── Restore Lambda ─────────────────────────────────────
resource "aws_lambda_function" "restore" {
  function_name    = "${var.project_name}-restore"
  role             = aws_iam_role.restore.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  filename         = data.archive_file.restore.output_path
  source_code_hash = data.archive_file.restore.output_base64sha256
  timeout          = 120
  memory_size      = 128

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  tags = var.common_tags
}

########################################################
# 5-1. Lambda Log Retention
########################################################

resource "aws_cloudwatch_log_group" "backup" {
  name              = "/aws/lambda/${aws_lambda_function.backup.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "cleanup" {
  name              = "/aws/lambda/${aws_lambda_function.cleanup.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "restore" {
  name              = "/aws/lambda/${aws_lambda_function.restore.function_name}"
  retention_in_days = 14
}

########################################################
# 6. EventBridge 스케줄러
########################################################

# ── 매시간 백업 (hourly) ───────────────────────────────
resource "aws_cloudwatch_event_rule" "backup_hourly" {
  name                = "${var.project_name}-backup-hourly"
  description         = "매시간 EBS 스냅샷 백업"
  schedule_expression = "rate(1 hour)"
  tags                = var.common_tags
}

resource "aws_cloudwatch_event_target" "backup_hourly" {
  rule  = aws_cloudwatch_event_rule.backup_hourly.name
  arn   = aws_lambda_function.backup.arn
  input = jsonencode({ schedule = "hourly" })
}

resource "aws_lambda_permission" "backup_hourly" {
  statement_id  = "AllowEventBridgeHourly"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_hourly.arn
}

# ── 매일 자정 백업 (daily) ─────────────────────────────
resource "aws_cloudwatch_event_rule" "backup_daily" {
  name                = "${var.project_name}-backup-daily"
  description         = "매일 자정 EBS 스냅샷 백업"
  schedule_expression = "cron(1 0 * * ? *)" # UTC 00:01 = KST 09:01 (1분 오프셋으로 hourly 트리거와 충돌 방지)
  tags                = var.common_tags
}

resource "aws_cloudwatch_event_target" "backup_daily" {
  rule  = aws_cloudwatch_event_rule.backup_daily.name
  arn   = aws_lambda_function.backup.arn
  input = jsonencode({ schedule = "daily" })
}

resource "aws_lambda_permission" "backup_daily" {
  statement_id  = "AllowEventBridgeDaily"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_daily.arn
}

# ── 매일 새벽 2시 정리 (cleanup) ──────────────────────
resource "aws_cloudwatch_event_rule" "cleanup_daily" {
  name                = "${var.project_name}-cleanup-daily"
  description         = "만료된 스냅샷 자동 삭제"
  schedule_expression = "cron(0 17 * * ? *)" # UTC 17:00 = KST 02:00
  tags                = var.common_tags
}

resource "aws_cloudwatch_event_target" "cleanup_daily" {
  rule = aws_cloudwatch_event_rule.cleanup_daily.name
  arn  = aws_lambda_function.cleanup.arn
}

resource "aws_lambda_permission" "cleanup_daily" {
  statement_id  = "AllowEventBridgeCleanup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup_daily.arn
}

########################################################
# 7. API Gateway REST API (수동 복구 엔드포인트 + API Key 인증)
########################################################

resource "aws_api_gateway_rest_api" "vault" {
  name        = "${var.project_name}-api"
  description = "Smart Vault restore API"
  tags        = var.common_tags
}

resource "aws_api_gateway_resource" "restore" {
  rest_api_id = aws_api_gateway_rest_api.vault.id
  parent_id   = aws_api_gateway_rest_api.vault.root_resource_id
  path_part   = "restore"
}

resource "aws_api_gateway_method" "restore" {
  rest_api_id      = aws_api_gateway_rest_api.vault.id
  resource_id      = aws_api_gateway_resource.restore.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true # API Key 없는 요청은 Gateway에서 403 반환
}

resource "aws_api_gateway_integration" "restore" {
  rest_api_id             = aws_api_gateway_rest_api.vault.id
  resource_id             = aws_api_gateway_resource.restore.id
  http_method             = aws_api_gateway_method.restore.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.restore.invoke_arn
}

resource "aws_api_gateway_deployment" "vault" {
  rest_api_id = aws_api_gateway_rest_api.vault.id
  depends_on = [
    aws_api_gateway_method.restore,
    aws_api_gateway_integration.restore,
  ]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "vault" {
  rest_api_id   = aws_api_gateway_rest_api.vault.id
  deployment_id = aws_api_gateway_deployment.vault.id
  stage_name    = "v1"
  tags          = var.common_tags
}

resource "aws_api_gateway_api_key" "restore" {
  name    = "${var.project_name}-restore-key"
  enabled = true
  tags    = var.common_tags
}

resource "aws_api_gateway_usage_plan" "vault" {
  name = "${var.project_name}-usage-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.vault.id
    stage  = aws_api_gateway_stage.vault.stage_name
  }
  tags = var.common_tags
}

resource "aws_api_gateway_usage_plan_key" "restore" {
  key_id        = aws_api_gateway_api_key.restore.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.vault.id
}

resource "aws_lambda_permission" "apigw_restore" {
  statement_id  = "AllowAPIGatewayRestore"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.restore.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.vault.execution_arn}/*/*"
}

########################################################
# 8. CloudWatch 알람 + 대시보드
########################################################

# Lambda 에러 알람
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = {
    backup  = aws_lambda_function.backup.function_name
    cleanup = aws_lambda_function.cleanup.function_name
    restore = aws_lambda_function.restore.function_name
  }

  alarm_name          = "${var.project_name}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "${each.key} Lambda 오류 발생"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = each.value }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.common_tags
}

# 백업 미실행 감지 알람 (6시간 동안 백업 Lambda 호출 없으면 알람)
resource "aws_cloudwatch_metric_alarm" "backup_not_running" {
  alarm_name          = "${var.project_name}-backup-not-running"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = 21600 # 6시간
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "6시간 동안 백업이 실행되지 않았습니다"
  treat_missing_data  = "breaching" # 데이터 없으면 알람 발생
  dimensions          = { FunctionName = aws_lambda_function.backup.function_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.common_tags
}

# 백업 실행 시간 과다 감지 알람 (240초 이상 실행되면 경고.)
resource "aws_cloudwatch_metric_alarm" "backup_duration" {
  alarm_name          = "${var.project_name}-backup-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Maximum"

  threshold = 240000

  dimensions = {
    FunctionName = aws_lambda_function.backup.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "vault" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title  = "Lambda 실행 현황"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.backup.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.cleanup.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.restore.function_name],
          ]
          period = 3600, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title  = "Lambda 에러"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.backup.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.cleanup.function_name],
          ]
          period = 3600, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title  = "아카이브 버킷 크기"
          region = var.aws_region
          metrics = [
            ["AWS/S3", "BucketSizeBytes",
              "BucketName", aws_s3_bucket.archive.id,
            "StorageType", "StandardStorage"]
          ]
          period = 86400, stat = "Average", view = "timeSeries"
        }
      },
    ]
  })
}



########################################################
# 테스트용 EC2 인스턴스 (백업 대상)
########################################################

# 계정에 기본 VPC가 없으므로 테스트용 VPC/서브넷을 직접 생성
resource "aws_vpc" "test" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name      = "smart-vault-test-vpc"
    ManagedBy = "terraform"
  }
}

resource "aws_subnet" "test" {
  vpc_id            = aws_vpc.test.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name      = "smart-vault-test-subnet"
    ManagedBy = "terraform"
  }
}

# 최신 Amazon Linux 2023 AMI 자동 조회
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# 테스트용 EC2 (t3.micro — ap-northeast-2 Free Tier)
resource "aws_instance" "backup_target" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.test.id

  tags = {
    Name        = "smart-vault-test-server"
    backup      = "true" # ← 이 태그 하나로 백업 대상 자동 등록
    Environment = "test"
    ManagedBy   = "terraform"
  }
}
