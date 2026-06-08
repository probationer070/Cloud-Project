# GitHub Actions CI Pipeline — Design Spec

**Date:** 2026-06-08
**Author:** Jaehwan
**Status:** approved

---

## Problem

The existing `terraform-init.yml` workflow only runs `terraform init` — a smoke test that
providers download. It does not validate HCL correctness, enforce formatting, or produce a
plan. For a portfolio project, this is not enough to demonstrate CI/CD competence.

---

## Solution

Replace the single-job init workflow with a 3-job pipeline using AWS OIDC authentication
(no long-lived credentials). Jobs: `fmt-check` → `validate` → `plan`. Each job depends on
the previous, so failures are caught at the cheapest stage first.

---

## Scope

- `terraform fmt -check` on all 5 projects
- `terraform validate` on all 5 projects (`-backend=false`, OIDC auth)
- `terraform plan` on all 5 projects (`-backend=false`, OIDC auth, read-only)
- CI badge on `README.md` pinned to `main` branch
- Plan output uploaded as workflow artifact
- No `terraform apply` — portfolio project, no live infrastructure

---

## AWS OIDC Setup (one-time, manual)

### Step 1 — Add GitHub OIDC identity provider in IAM

- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

### Step 2 — Create IAM role `github-actions-readonly`

Trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_USERNAME/Cloud-Project:*"
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### Step 3 — Attach `ReadOnlyAccess` managed policy

`ReadOnlyAccess` is generally sufficient for most `terraform plan` runs, but some providers
or resource types may require additional read permissions not covered by this policy.

### Step 4 — Store role ARN in GitHub Secret

GitHub repo → Settings → Secrets → Actions → New secret:
- Name: `AWS_ROLE_ARN`
- Value: `arn:aws:iam::ACCOUNT_ID:role/github-actions-readonly`

---

## File Changes

| File | Action |
|------|--------|
| `.github/workflows/terraform-ci.yml` | Create — 3-job pipeline |
| `.github/workflows/terraform-init.yml` | Delete |
| `init-all.sh` | Update — `validate`/`plan` command + `TF_INIT_FLAGS` + plan artifact output |
| `README.md` | Add CI badge pinned to `main` |

---

## Workflow: `.github/workflows/terraform-ci.yml`

```yaml
name: Terraform CI

on:
  push:
    branches: [main, Testo]
  pull_request:

concurrency:
  group: terraform-ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  id-token: write
  contents: read

env:
  TF_PLUGIN_CACHE_DIR: ${{ github.workspace }}/.terraform.d/plugin-cache

jobs:
  fmt-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.12.2

      - name: Check formatting
        run: |
          for dir in project*/; do
            echo "=== fmt check: $dir ==="
            terraform -chdir="$dir" fmt -check -recursive
          done

  validate:
    needs: fmt-check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.12.2

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-northeast-2

      - name: Create plugin cache dir
        run: |
          mkdir -p "$TF_PLUGIN_CACHE_DIR"
          cat > ~/.terraformrc <<EOF
          plugin_cache_dir = "$TF_PLUGIN_CACHE_DIR"
          EOF

      - uses: actions/cache@v4
        with:
          path: ${{ env.TF_PLUGIN_CACHE_DIR }}
          key: terraform-${{ hashFiles('**/.terraform.lock.hcl') }}
          restore-keys: terraform-

      - name: Init and validate all projects
        run: TF_INIT_FLAGS="-backend=false" bash init-all.sh validate

  plan:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.12.2

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-northeast-2

      - name: Create plugin cache dir
        run: |
          mkdir -p "$TF_PLUGIN_CACHE_DIR"
          cat > ~/.terraformrc <<EOF
          plugin_cache_dir = "$TF_PLUGIN_CACHE_DIR"
          EOF

      - uses: actions/cache@v4
        with:
          path: ${{ env.TF_PLUGIN_CACHE_DIR }}
          key: terraform-${{ hashFiles('**/.terraform.lock.hcl') }}
          restore-keys: terraform-

      - name: Plan all projects
        run: TF_INIT_FLAGS="-backend=false" bash init-all.sh plan

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: terraform-plan
          path: "**/plan.txt"
```

---

## Updated `init-all.sh`

```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMAND=${1:-""}
TF_INIT_FLAGS=${TF_INIT_FLAGS:-""}

projects=()
for dir in "$SCRIPT_DIR"/project*/; do
  [ -d "$dir" ] && [ -f "$dir/main.tf" ] && projects+=("$dir")
done

if [ "${#projects[@]}" -eq 0 ]; then
  echo "Error: No Terraform projects found under $SCRIPT_DIR" >&2
  exit 1
fi

for dir in "${projects[@]}"; do
  name=$(basename "$dir")
  echo "=== $name ==="
  (
    cd "$dir"
    terraform init -input=false $TF_INIT_FLAGS
    [ "$COMMAND" = "validate" ] && terraform validate
    if [ "$COMMAND" = "plan" ]; then
      terraform plan -input=false -detailed-exitcode -out=tfplan || [ $? -eq 2 ]
      terraform show -no-color tfplan > plan.txt
    fi
  )
done

echo "=== All ${#projects[@]} projects: ${COMMAND:-init} complete ==="
```

---

## README Badge

Add at top of `README.md`, replacing `YOUR_USERNAME`:

```markdown
![Terraform CI](https://github.com/YOUR_USERNAME/Cloud-Project/actions/workflows/terraform-ci.yml/badge.svg?branch=main)
```

Pinned to `main` so the badge always reflects the stable branch status.

---

## Out of Scope

- `terraform apply` — no live infrastructure
- Python linting (flake8/ruff) — add in a future iteration
- tfsec / checkov security scanning — add when P5 is stable
- Separate per-project jobs — single job per stage is sufficient for portfolio
