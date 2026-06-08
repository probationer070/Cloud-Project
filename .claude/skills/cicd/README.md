# /cicd

**When to run:** After adding a new Lambda function, Terraform resource, or project directory.

## What it checks

### Part 1 — Terraform wiring

| For new Lambda | For new project |
|---------------|-----------------|
| `aws_lambda_function` in `main.tf` | `backend.tf` pointing to bootstrap S3 |
| CloudWatch log group + `retention_in_days` | `terraform.tfvars` present (gitignored) |
| `aws_lambda_permission` for trigger | `variables.tf` has `aws_region`, `project_name`, `suffix`, `common_tags` |
| IAM role + least-privilege policy in `iam.tf` | |
| Input variables in `variables.tf` | |
| Endpoint / ARN exported in `outputs.tf` | |

### Part 2 — GitHub Actions

- New project directory included in `.github/workflows/terraform-init.yml` matrix
- No hardcoded AWS credentials — uses `${{ secrets.AWS_ACCESS_KEY_ID }}`
- Workflow path references the correct project directory

## Output tags

| Tag | Meaning | Action required |
|-----|---------|-----------------|
| `[MISSING]` | Required wiring absent | Add before deploy |
| `[WARN]` | Present but misconfigured | Fix or justify deferral |
| `[OK]` | Confirmed correct | No action |

## Example

```
/cicd
```

```
## /cicd — 26-06-08

### Findings
[MISSING] project5-document-engine/outputs.tf — query API endpoint URL not exported
[WARN]    .github/workflows/terraform-init.yml:12 — project5 not in directory matrix
[OK]      project5-document-engine/backend.tf — remote state backend correctly keyed

### Summary
1 MISSING and 1 WARN to address before deploy.

### Next step
Add query_api_endpoint to outputs.tf, then add project5-document-engine to workflow matrix.
```

## Tips

- Always run `/cicd` before the first `terraform apply` on a new project — a missing `backend.tf` will cause state to be created locally and is hard to migrate later (see ERR-001).
- `[MISSING]` on `outputs.tf` means the next session won't know the endpoint URL without going to the AWS console.
- Hardcoded credentials in workflow YAML are a `[BLOCK]`-level security issue — treat them as such even though `/cicd` uses `[WARN]`.
