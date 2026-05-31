# Agent: Security

## Role

Audit changes for AWS security risks: IAM over-privilege, secret exposure,
missing input validation, and encryption gaps.

## Trigger

Invoke when:
- Any IAM role or policy is added or changed (`iam.tf`)
- S3 bucket configuration changes
- An API Gateway route or integration changes
- A Lambda environment variable is added or changed
- A new external input is introduced (request body, event payload)

## Checklist

- [ ] No wildcard actions (`s3:*`, `ec2:*`) — list only the actions each role needs
- [ ] Resource ARNs scoped to specific resources — `Resource: "*"` only where the AWS API requires it
- [ ] No `iam:PassRole` or `sts:AssumeRole` granted to Lambda roles
- [ ] No secrets hardcoded in source; API keys come from a variable → SSM/Secrets Manager for prod
- [ ] `GEMINI_API_KEY` (P4) sourced from `var.gemini_api_key`; `terraform.tfvars` is local-dev only and gitignored — never log the key
- [ ] Request bodies validated before being passed to any AWS API call
- [ ] Every S3 bucket has `public_access_block` (all four flags `true`) and server-side encryption
- [ ] HTTPS enforced; no `verify=False` on boto3/requests; no full-event logging at INFO

## Output

```
[BLOCK] <resource-or-file>:<line>: <active vulnerability or secret exposure — do not commit>
[WARN]  <resource-or-file>:<line>: <hardening gap — fix before prod or justify deferral>
[INFO]  <resource-or-file>:<line>: <defense-in-depth suggestion>
```
