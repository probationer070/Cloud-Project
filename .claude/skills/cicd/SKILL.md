# CI/CD Check

Run after adding a new resource, Lambda function, or project to verify Terraform wiring
is complete and GitHub Actions workflows cover the new component.

## How to use

Type `/cicd` after adding any new Lambda function, Terraform resource, or project directory.

## Steps

1. Identify the new resource or function from the current diff.
2. Run Part 1 (Terraform wiring) against the relevant project's Terraform files.
3. Run Part 2 (GitHub Actions) against `.github/workflows/`.
4. Report findings using the output format.

## Part 1 — Terraform wiring

For each new Lambda function:
- [ ] `aws_lambda_function` resource present in `main.tf`
- [ ] `aws_cloudwatch_log_group` for the function in `main.tf` (`retention_in_days` set)
- [ ] `aws_lambda_permission` for the trigger (S3, API Gateway, or EventBridge) in `main.tf`
- [ ] IAM role and policy in `iam.tf` — least-privilege actions only
- [ ] New input values declared as variables in `variables.tf` (not hardcoded in `main.tf`)
- [ ] Endpoint URL or function ARN exported in `outputs.tf`

For each new project directory:
- [ ] `backend.tf` present pointing to bootstrap S3 bucket with unique key (`p[N]/terraform.tfstate`)
- [ ] `terraform.tfvars` present (gitignored) with `suffix` and `alert_email` filled in
- [ ] `variables.tf` declares `aws_region`, `project_name`, `suffix`, `common_tags` at minimum

## Part 2 — GitHub Actions

- [ ] `.github/workflows/terraform-init.yml` (or equivalent) includes the new project directory
- [ ] Workflow does not hardcode AWS credentials — uses `${{ secrets.AWS_ACCESS_KEY_ID }}` pattern
- [ ] Workflow references the correct relative path to the project directory
- [ ] No new workflow file introduces a `pull_request` trigger without environment protection

## Output format

```
## /cicd — YYYY-MM-DD

### Findings
[MISSING] project5-document-engine/outputs.tf — query API endpoint URL not exported
[WARN]    .github/workflows/terraform-init.yml:12 — project5 directory not in matrix
[OK]      project5-document-engine/backend.tf — remote state backend present and correctly keyed

### Summary
1 MISSING and 1 WARN to address before deploy.

### Next step
Add query_api_endpoint output to project5-document-engine/outputs.tf, then add
project5-document-engine to the workflow matrix at .github/workflows/terraform-init.yml:12.
```

If no findings: write `No findings — all checks pass.` under Findings.
