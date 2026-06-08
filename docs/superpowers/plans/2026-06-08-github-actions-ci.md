# GitHub Actions CI Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing single-job `terraform-init.yml` with a production-quality 3-job CI pipeline (`fmt-check` → `validate` → `plan`) using AWS OIDC authentication.

**Architecture:** Three dependent jobs run on every push/PR: format check (no AWS), validate (OIDC + `-backend=false`), plan (OIDC + `-backend=false` + artifact upload). A shared `init-all.sh` script handles all three stages via a `COMMAND` argument. No `terraform apply` — portfolio project only.

**Tech Stack:** GitHub Actions, Terraform 1.12.2, `hashicorp/setup-terraform@v3`, `aws-actions/configure-aws-credentials@v4`, `actions/cache@v4`, `actions/upload-artifact@v4`.

---

## File Map

| File | Action |
|------|--------|
| `init-all.sh` | Modify — add `COMMAND` arg, `TF_INIT_FLAGS` env var, `plan.txt` output |
| `.github/workflows/terraform-ci.yml` | Create — 3-job pipeline |
| `.github/workflows/terraform-init.yml` | Delete |
| `README.md` | Modify — add CI badge at top |

---

## Prerequisites (manual — do before running this plan)

Before the `validate` and `plan` jobs will pass, complete the AWS OIDC setup:

1. **AWS Console → IAM → Identity providers → Add provider**
   - Provider type: OpenID Connect
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

2. **AWS Console → IAM → Roles → Create role**
   - Trusted entity: Web identity → select the provider above
   - Condition: `token.actions.githubusercontent.com:sub` = `repo:probationer070/Cloud-Project:*`
   - Condition: `token.actions.githubusercontent.com:aud` = `sts.amazonaws.com`
   - Attach policy: `ReadOnlyAccess`
   - Role name: `github-actions-readonly`
   - Copy the role ARN (format: `arn:aws:iam::ACCOUNT_ID:role/github-actions-readonly`)

3. **GitHub repo → Settings → Secrets and variables → Actions → New repository secret**
   - Name: `AWS_ROLE_ARN`
   - Value: the role ARN from step 2

---

### Task 1: Update `init-all.sh`

**Files:**
- Modify: `init-all.sh`

- [ ] **Step 1: Verify the current content**

Run: `cat init-all.sh`
Expected output:
```bash
#!/usr/bin/env bash
set -e
...
(cd "$dir" && terraform init -input=false)
...
```
Confirm the file exists and has no `COMMAND` or `TF_INIT_FLAGS` logic yet.

- [ ] **Step 2: Replace the file with the updated version**

Write `init-all.sh` with this exact content:

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

- [ ] **Step 3: Verify bash syntax**

Run: `bash -n init-all.sh`
Expected: no output, exit code 0 (syntax is valid).

- [ ] **Step 4: Verify backward compatibility — init-only still works**

Run: `bash init-all.sh --help 2>&1 || true`
The script accepts an unknown first arg without crashing (it just won't match `validate` or `plan`, so no extra commands run). The `--help` case is ignored gracefully.

---

### Task 2: Create `.github/workflows/terraform-ci.yml`

**Files:**
- Create: `.github/workflows/terraform-ci.yml`

- [ ] **Step 1: Create the workflow file with this exact content**

Write `.github/workflows/terraform-ci.yml`:

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

      - name: Create plugin cache dir and configure Terraform
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

      - name: Create plugin cache dir and configure Terraform
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

- [ ] **Step 2: Verify the file was created**

Run: `head -3 .github/workflows/terraform-ci.yml`
Expected:
```
name: Terraform CI

on:
```

---

### Task 3: Delete the old workflow

**Files:**
- Delete: `.github/workflows/terraform-init.yml`

- [ ] **Step 1: Confirm the file exists before deleting**

Run: `ls .github/workflows/`
Expected: `terraform-init.yml` and `terraform-ci.yml` both present.

- [ ] **Step 2: Delete the old workflow**

Run: `git rm .github/workflows/terraform-init.yml`
Expected output: `rm '.github/workflows/terraform-init.yml'`

- [ ] **Step 3: Verify only the new workflow remains**

Run: `ls .github/workflows/`
Expected: only `terraform-ci.yml`.

---

### Task 4: Add CI badge to `README.md`

**Files:**
- Modify: `README.md` line 1

- [ ] **Step 1: Read the current first line**

Run: `head -1 README.md`
Expected: `# Cloud Project — AWS Hands-On Portfolio (P1–P4)`

- [ ] **Step 2: Insert the badge before the title**

Edit `README.md` — find this exact text at the top:

```
# Cloud Project — AWS Hands-On Portfolio (P1–P4)
```

Replace with:

```
![Terraform CI](https://github.com/probationer070/Cloud-Project/actions/workflows/terraform-ci.yml/badge.svg?branch=main)

# Cloud Project — AWS Hands-On Portfolio (P1–P4)
```

- [ ] **Step 3: Verify the badge line is first**

Run: `head -3 README.md`
Expected:
```
![Terraform CI](https://github.com/probationer070/Cloud-Project/actions/workflows/terraform-ci.yml/badge.svg?branch=main)

# Cloud Project — AWS Hands-On Portfolio (P1–P4)
```

---

### Task 5: Commit and push

- [ ] **Step 1: Stage all changes**

```bash
git add init-all.sh \
        .github/workflows/terraform-ci.yml \
        README.md
```

(The `git rm` in Task 3 already staged the deletion.)

- [ ] **Step 2: Verify staged files**

Run: `git status`
Expected — staged:
```
deleted:  .github/workflows/terraform-init.yml
new file: .github/workflows/terraform-ci.yml
modified: init-all.sh
modified: README.md
```
No unintended files.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: replace terraform-init with 3-job CI pipeline (fmt/validate/plan)

Add terraform-ci.yml: fmt-check → validate → plan jobs with OIDC auth,
Terraform 1.12.2 pinned, concurrency cancel, plugin cache via .terraformrc,
lock.hcl-keyed cache, and plan artifact upload.

Update init-all.sh to accept validate/plan commands and TF_INIT_FLAGS.
Add CI badge to README.md.

AWS OIDC setup: IAM role github-actions-readonly + ReadOnlyAccess policy.
AWS_ROLE_ARN stored as GitHub Actions secret.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Push and verify the workflow triggers**

Run: `git push`

Then open: `https://github.com/probationer070/Cloud-Project/actions`

Expected: a new `Terraform CI` workflow run appears for the pushed commit.
The `fmt-check` job should pass immediately (no AWS needed).
The `validate` and `plan` jobs require the OIDC prerequisite from the Prerequisites section above.

---

## Self-Review

**Spec coverage:**
- `terraform fmt -check` — Task 2 `fmt-check` job ✓
- `terraform validate` with `-backend=false` — Task 2 `validate` job + Task 1 `init-all.sh` ✓
- `terraform plan` with `-backend=false` — Task 2 `plan` job + Task 1 `init-all.sh` ✓
- OIDC auth — Task 2 `configure-aws-credentials` steps ✓
- Terraform 1.12.2 pinned — all 3 jobs ✓
- Concurrency control — `concurrency` block ✓
- `.terraformrc` plugin cache — `Create plugin cache dir` steps ✓
- `lock.hcl` cache key — `actions/cache` steps ✓
- Plan artifact upload — `upload-artifact` step ✓
- CI badge pinned to `main` — Task 4 ✓
- Delete old workflow — Task 3 ✓
- `ReadOnlyAccess` note — Prerequisites section ✓

**Placeholder scan:** No TBD, TODO, or vague steps. Badge URL uses real GitHub username `probationer070`. All commands show expected output.

**Consistency:** `TF_INIT_FLAGS` used consistently in Task 1 (script) and Task 2 (workflow `run:` lines). `COMMAND` argument matches `validate`/`plan` string checks in `init-all.sh`.
