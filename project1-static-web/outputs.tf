########################################################
# outputs.tf — apply 후 확인할 값들
########################################################

output "s3_bucket_name" {
  description = "S3 버킷 이름"
  value       = aws_s3_bucket.website.id
}

output "cloudfront_domain" {
  description = "CloudFront 배포 도메인 (바로 접속 가능)"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront 배포 ID (캐시 무효화 시 사용)"
  value       = aws_cloudfront_distribution.website.id
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.website.arn
}

output "sns_topic_arn" {
  description = "알림 SNS 토픽 ARN"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch 대시보드 URL"
  value       = "https://ap-northeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#dashboards:name=${aws_cloudwatch_dashboard.website.dashboard_name}"
}

output "upload_command" {
  description = "정적 파일 업로드 명령어"
  value       = "aws s3 sync ./website/ s3://${aws_s3_bucket.website.id}/ --delete"
}

output "cache_invalidation_command" {
  description = "CloudFront 캐시 무효화 명령어"
  value       = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.website.id} --paths '/*'"
}
