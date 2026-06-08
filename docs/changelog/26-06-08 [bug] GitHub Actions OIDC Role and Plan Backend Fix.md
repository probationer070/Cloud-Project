# 26-06-08 [bug] GitHub Actions OIDC Role and Plan Backend Fix

**Type:** bug
**Branch / Commit:** Testo / 79b4687

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `bootstrap/main.tf` | `aws_iam_openid_connect_provider.github` | New — registers GitHub Actions OIDC provider in AWS IAM |
| `bootstrap/main.tf` | `aws_iam_role.github_actions` | New — IAM role CI assumes via OIDC; trust scoped to this repo |
| `bootstrap/main.tf` | `aws_iam_role_policy.github_actions_terraform` | New — least-privilege policy: S3 state read/write + read-only for all services used in plan |
| `bootstrap/outputs.tf` | `github_actions_role_arn` | New output — prints role ARN to paste into `AWS_ROLE_ARN` secret |
| `.github/workflows/terraform-ci.yml` | `plan` job `run` step | Removed `TF_INIT_FLAGS="-backend=false"` so plan uses the real S3 backend |

## Why Changed

Two separate CI failures blocked the pipeline:

1. **OIDC role missing** — `AWS_ROLE_ARN` secret was unset because the IAM role had never been created. The `configure-aws-credentials` action failed with "Request ARN is invalid" on every run. Root cause: bootstrap only created the S3 state bucket; the GitHub Actions trust relationship was never provisioned.

2. **Backend mismatch in plan job** — The `plan` job ran `terraform init -backend=false` then `terraform plan`. Terraform detected the `backend "s3" {}` block in each project's `backend.tf`, found it conflicted with the `-backend=false` init, and refused to continue with "Backend initialization required." The `validate` job correctly uses `-backend=false` (no state needed), but `plan` must init against the real S3 backend.

## Contents Diff

**`.github/workflows/terraform-ci.yml` — plan job**
```yaml
# Before
- name: Plan all projects
  run: TF_INIT_FLAGS="-backend=false" bash init-all.sh plan

# After
- name: Plan all projects
  run: bash init-all.sh plan
```

## Improvements

- CI pipeline can now authenticate to AWS without storing long-lived credentials in GitHub secrets — OIDC token exchange is used instead.
- `terraform plan` now reads and writes real remote state, so plan output reflects actual infrastructure drift rather than a stateless dry run.
- `github_actions_role_arn` output eliminates manual ARN lookup after bootstrap apply.

## Performance Impact

- `plan` job now performs a real S3 backend init; adds ~2–3 s per project for state fetch. No impact on `fmt-check` or `validate` jobs.
- IAM policy is additive to bootstrap (no existing resources changed); `terraform apply` on bootstrap is a no-op for all S3 resources.

## Agents Consulted

none

## Findings Addressed

none

## Findings Deferred

none
