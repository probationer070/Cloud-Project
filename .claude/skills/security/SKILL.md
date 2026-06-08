# Security Review

Run after any Terraform or Lambda change to catch IAM over-privilege, secret exposure,
missing encryption, and backend gaps before committing.

## How to use

Type `/security` after modifying any of: `iam.tf`, `main.tf`, `lambda/*/index.py`,
`backend.tf`, or any SSM-related code.

## Steps

1. Read the current diff (`git diff HEAD`) and identify which files changed.
2. For each changed file, run the relevant checklist section below.
3. Report all findings using the output format at the bottom.

## Checklist

### `iam.tf` — IAM roles and policies
- [ ] No wildcard actions (`s3:*`, `ec2:*`, `lambda:*`) — list only the actions each role needs
- [ ] Resource ARNs scoped to specific resources — `Resource: "*"` only where the AWS API requires it
- [ ] No `iam:PassRole` or `sts:AssumeRole` granted to Lambda roles
- [ ] Policy names follow `p[N]-` prefix convention (e.g., `p4-chatbot-policy`)

### `main.tf` — Infrastructure resources
- [ ] Every S3 bucket has `aws_s3_bucket_public_access_block` with all four flags `true`
- [ ] Every S3 bucket has `aws_s3_bucket_server_side_encryption_configuration` with `AES256`
- [ ] API Gateway routes do not expose internal resource ARNs in responses
- [ ] Lambda timeouts are set appropriately (Ingest ≤ 300s, Query ≤ 60s, Chatbot ≤ 30s)

### `lambda/*/index.py` — Lambda function code
- [ ] No secrets or API keys hardcoded — all sourced from `os.environ` via SSM/Parameter Store
- [ ] No `verify=False` on boto3 clients or requests calls
- [ ] No full event payload logged at INFO level — log only safe fields (session_id, doc_id, status)
- [ ] Input from request body validated before being passed to any AWS API call

### SSM / Parameter Store usage
- [ ] API keys fetched via `ssm.get_parameter(Name=..., WithDecryption=True)`
- [ ] SSM parameter created by Terraform with `ignore_changes = [value]` — seeded separately via CLI
- [ ] Parameter name follows `/p[N]/service/key-name` convention

### `backend.tf` — Remote state
- [ ] `backend.tf` present in any new project directory before first `terraform apply`
- [ ] Points to the bootstrap S3 bucket with a unique `key` per project (e.g., `p5/terraform.tfstate`)
- [ ] State bucket has versioning and encryption (confirmed in `bootstrap/main.tf`)

## Output format

```
## /security — YYYY-MM-DD

### Findings
[BLOCK] iam.tf:14 — Lambda role grants s3:* on Resource: "*"
[WARN]  lambda/chatbot/index.py:23 — full event dict logged at INFO level
[INFO]  main.tf:45 — consider enabling S3 access logging for audit trail

### Summary
2 findings: 1 BLOCK must be fixed before commit, 1 WARN to address.

### Next step
Fix iam.tf:14 — replace s3:* with s3:GetObject, s3:PutObject scoped to the specific bucket ARN.
```

If no findings: write `No findings — all checks pass.` under Findings.
