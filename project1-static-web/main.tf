########################################################
# Project 1: 보안/성능 최적화 정적 웹사이트
# S3 + CloudFront + ACM + WAF + CloudWatch
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

# 기본 리전 (서울)
provider "aws" {
  region = var.aws_region
}

# ACM 인증서는 반드시 us-east-1 에 생성해야 CloudFront에서 사용 가능
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

########################################################
# 1. S3 버킷 (정적 파일 호스팅)
########################################################

resource "aws_s3_bucket" "website" {
  bucket        = var.bucket_name
  force_destroy = true # 테스트용: 버킷 안 파일도 함께 삭제

  tags = var.common_tags
}

# 퍼블릭 접근 차단 (CloudFront OAC를 통해서만 접근)
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 버킷 버전 관리 활성화
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 서버 사이드 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 버킷 정책: CloudFront OAC만 허용
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })
}

########################################################
# 2. ACM 인증서 (us-east-1에 생성)
# ※ 도메인 없이 테스트 시 이 블록을 주석 처리하고
#    cloudfront_distribution의 viewer_certificate를
#    cloudfront_default_certificate = true 로 변경하세요
########################################################

# resource "aws_acm_certificate" "website" {
#   provider          = aws.us_east_1
#   domain_name       = var.domain_name
#   validation_method = "DNS"
#   tags              = var.common_tags
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }

########################################################
# 3. WAF (us-east-1에 생성 — CloudFront 전용)
########################################################

resource "aws_wafv2_web_acl" "website" {
  provider    = aws.us_east_1
  name        = "${var.project_name}-waf"
  description = "WAF for ${var.project_name} CloudFront"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # 규칙 1: AWS 관리형 공통 규칙 (SQLi, XSS 등 차단)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # 규칙 2: 악성 IP 차단 (Amazon IP Reputation List) - !!! Fixed it
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {

        name        = "AWSManagedRulesAmazonIpReputationList" # <- 기존 ManagedRuleSet에서 올바른 이름으로 수정
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSIPReputationMetric"
      sampled_requests_enabled   = true
    }
  }

  # 규칙 3: Rate Limiting (IP당 5분간 2000 요청 초과 시 차단)
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf-metric"
    sampled_requests_enabled   = true
  }

  tags = var.common_tags
}

########################################################
# 4. CloudFront OAC (Origin Access Control)
########################################################

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for ${var.project_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

########################################################
# 5. CloudFront 배포
########################################################

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.project_name} distribution"
  web_acl_id          = aws_wafv2_web_acl.website.arn

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3-${var.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${var.bucket_name}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https" # HTTP → HTTPS 자동 리다이렉트

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600  # 1시간 캐시
    max_ttl     = 86400 # 최대 24시간
  }

  # SPA(React 등) 사용 시: 404/403을 index.html로 라우팅
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  # 도메인 없이 테스트 시 아래 설정 사용
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # 도메인 있을 때는 아래로 교체:
  # aliases = [var.domain_name]
  # viewer_certificate {
  #   acm_certificate_arn      = aws_acm_certificate.website.arn
  #   ssl_support_method       = "sni-only"
  #   minimum_protocol_version = "TLSv1.2_2021"
  # }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = var.common_tags
}

########################################################
# 6. CloudWatch 모니터링
########################################################

# 4xx 에러율 알람
resource "aws_cloudwatch_metric_alarm" "cloudfront_4xx_errors" {
  alarm_name          = "${var.project_name}-4xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300 # 5분
  statistic           = "Average"
  threshold           = 5 # 5% 초과 시 알람
  alarm_description   = "CloudFront 4xx 에러율이 5%를 초과했습니다"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.website.id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.common_tags
}

# 5xx 에러율 알람
resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx_errors" {
  alarm_name          = "${var.project_name}-5xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 1 # 1% 초과 시 즉시 알람
  alarm_description   = "CloudFront 5xx 에러율이 1%를 초과했습니다"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.website.id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.common_tags
}

# WAF 차단 요청 알람 (!!! 알람 액션을 버지니아 북부 SNS 토픽으로 변경)
resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  provider            = aws.us_east_1
  alarm_name          = "${var.project_name}-waf-blocked"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 100 # 5분간 100건 초과 시 알람
  alarm_description   = "WAF가 5분간 100건 이상의 요청을 차단했습니다"
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.website.name
    Region = "us-east-1"
    Rule   = "ALL"
  }

  alarm_actions = [aws_sns_topic.alerts_us_east_1.arn]
  tags          = var.common_tags
}

########################################################
# 7. SNS 알림 토픽
########################################################

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = var.common_tags
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# [추가] 버지니아 북부 리전(us-east-1)용 SNS 토픽 !!!
resource "aws_sns_topic" "alerts_us_east_1" {
  provider = aws.us_east_1 # 👈 버지니아 북부에 생성하도록 강제
  name     = "${var.project_name}-alerts-us-east-1"
  tags     = var.common_tags
}

resource "aws_sns_topic_subscription" "email_alert_us_east_1" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alerts_us_east_1.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

########################################################
# 8. CloudWatch 대시보드
########################################################

resource "aws_cloudwatch_dashboard" "website" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "CloudFront 요청 수"
          region = "us-east-1"
          metrics = [
            ["AWS/CloudFront", "Requests",
              "DistributionId", aws_cloudfront_distribution.website.id,
            "Region", "Global"]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "에러율 (4xx / 5xx)"
          region = "us-east-1"
          metrics = [
            ["AWS/CloudFront", "4xxErrorRate",
              "DistributionId", aws_cloudfront_distribution.website.id,
            "Region", "Global"],
            ["AWS/CloudFront", "5xxErrorRate",
              "DistributionId", aws_cloudfront_distribution.website.id,
            "Region", "Global"]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "CloudFront 캐시 히트율"
          region = "us-east-1"
          metrics = [
            ["AWS/CloudFront", "CacheHitRate",
              "DistributionId", aws_cloudfront_distribution.website.id,
            "Region", "Global"]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "WAF 차단 요청"
          region = "us-east-1"
          metrics = [
            ["AWS/WAFV2", "BlockedRequests",
              "WebACL", aws_wafv2_web_acl.website.name,
              "Region", "us-east-1",
            "Rule", "ALL"]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      }
    ]
  })
}
