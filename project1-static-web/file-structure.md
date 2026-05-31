# P1 File Structure — Static Web

```
project1-static-web/
│
├── main.tf               # All infrastructure: S3, WAF, CloudFront OAC,
│                         #   CloudFront distribution, CloudWatch alarms,
│                         #   SNS topics (Seoul + us-east-1), dashboard
│
├── variables.tf          # bucket_name, alert_email, domain_name,
│                         #   aws_region, project_name, common_tags
│
├── outputs.tf            # cloudfront_url, s3_upload_command,
│                         #   cloudfront_invalidation_command
│
├── website/
│   └── index.html        # Test static page; deploy with s3 sync
│
├── terraform.tfstate     # Local state (gitignored)
└── terraform.tfstate.backup
```

## Key relationships

- `main.tf` has two AWS providers: `ap-northeast-2` (S3, SNS, alarms) and `us-east-1` (WAF, SNS alarm target) — CloudFront requires WAF and ACM in `us-east-1`.
- S3 bucket is private. Only path to content is CloudFront → OAC → S3. Bucket policy enforces this via `AWS:SourceArn` condition.
- WAF Web ACL is attached to CloudFront via `web_acl_id`. It is created in `us-east-1` even though the distribution is global.
- CloudWatch alarm for WAF blocked requests uses the `us-east-1` SNS topic because WAF metrics are only in `us-east-1`.

## Deploy / update flow

```
terraform apply          → provision/update infrastructure
aws s3 sync ./website/ s3://[bucket]/ --delete   → upload UI
aws cloudfront create-invalidation ...           → flush CDN cache
```

## Design reference

[Full architecture and security notes](../docs/design/p1-static-web/design.md)
