# 26-06-08 [upgrade] GitHub Actions CI Pipeline with OIDC

**Type:** upgrade
**Branch / Commit:** Testo / 2b0c7d8

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `.github/workflows/terraform-ci.yml` | (new file) | 3-job pipeline: fmt-check → validate → plan |
| `.github/workflows/terraform-init.yml` | (deleted) | Replaced by terraform-ci.yml |
| `init-all.sh` | main project loop | Added COMMAND arg, TF_INIT_FLAGS env var, validate/plan logic, plan.txt output |
| `README.md` | top of file | Added CI badge pinned to main branch |

## Why Changed

The existing `terraform-init.yml` only ran `terraform init` — a smoke test that providers
download. It proved nothing about HCL correctness or infrastructure validity. For a portfolio
project the CI tab needs to show a real quality gate. Replaced with a 3-job pipeline using
AWS OIDC (no long-lived credentials stored in GitHub Secrets): fmt-check catches formatting
issues cheapest, validate proves HCL is correct, plan shows what would change and uploads
the output as a workflow artifact.

## Contents Diff

**`init-all.sh` — main project loop**

```bash
# Before
for dir in "${projects[@]}"; do
    name=$(basename "$dir")
    echo "=== Initializing $name ==="
    (cd "$dir" && terraform init -input=false)
done

echo "=== All ${#projects[@]} projects initialized ==="

# After
COMMAND=${1:-""}
TF_INIT_FLAGS=${TF_INIT_FLAGS:-""}

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

## Improvements

- `terraform fmt -check` on all 5 projects catches formatting drift before validate runs
- `terraform validate` proves HCL configuration is correct on every push/PR
- `terraform plan` produces a readable diff uploaded as a workflow artifact for review
- OIDC authentication: no AWS access keys stored in GitHub Secrets — short-lived tokens per run
- Terraform pinned to 1.12.2 — prevents unexpected failures from upstream releases
- Concurrency control cancels stale runs when a new commit is pushed to the same branch
- `.terraformrc` written during setup so the plugin cache directory is actually used by Terraform
- Cache keyed on `**/.terraform.lock.hcl` (invalidates when provider versions change, not just when main.tf changes)
- CI badge on README.md pinned to `main` branch — visible proof of passing CI on the landing page

## Performance Impact

CI runtime increased from ~1 min (init-only) to ~5 min (fmt + validate + plan across 5 projects).
Provider cache reduces subsequent runs by ~2 min after first warm cache hit.
`init-all.sh` line count: 21 → 31 (+10 lines).

## Agents Consulted

`/cicd`, `/security`

## Findings Addressed

none (new feature)

## Findings Deferred

none
