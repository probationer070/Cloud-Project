# 26-06-06 [upgrade] P4 S3 Remote Backend and Bootstrap

**Type:** upgrade
**Branch / Commit:** Testo / (pending commit)
**Status:** Applied & verified 2026-06-06 — bootstrap state bucket live in account
`322551983602` (ap-northeast-2); P4 migrated to the S3 backend and rebuilt (24 resources);
`terraform plan` reports "No changes" (state matches deployed reality).

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `bootstrap/main.tf` | (new) | S3 state bucket (versioning, AES256 SSE, public-access-block ×4, TLS-only deny policy) — no DynamoDB; locking via native S3 lockfile |
| `bootstrap/variables.tf` | (new) | `aws_region`, `state_bucket_name`, `common_tags` |
| `bootstrap/outputs.tf` | (new) | `state_bucket` output to copy into backend.tf |
| `bootstrap/README.md` | (new) | Bootstrap-first setup runbook + `NoSuchBucket` troubleshooting |
| `project4-ai-chatbot/backend.tf` | (new) | `backend "s3"` block with `use_lockfile = true`, migrating P4 from local to shared remote state |
| `.agents/security.md` | Checklist | Added pre-apply check: remote backend configured + non-empty state on a live stack |
| `docs/adr/0002-s3-remote-state-backend.md` | (new) | ADR for the remote-backend decision (native lockfile) |
| `docs/error/ERR-001-...md`, `docs/error/README.md` | — | Recorded + resolved the root-cause error |

## Why Changed

`terraform apply` on the desktop failed with five `*AlreadyExists` errors
(IAM role, DynamoDB table, CloudWatch log group, S3 bucket, CloudFront OAC). Root cause
(ERR-001): P4 used **local state**. The laptop deployed the full 22-resource stack, but
`*.tfstate` is gitignored, so git synced only the `.tf` config — the desktop's empty state
tried to re-create resources that already exist in the shared AWS account. Local state
cannot be shared across machines; the fix is a remote backend.

## Contents Diff

New files — no before/after. Net effect on P4: state location moves from on-disk
`terraform.tfstate` to `s3://cloud-portfolio-tfstate-jaehwan-20260606/project4-ai-chatbot/terraform.tfstate`,
with locking via a native S3 lockfile (no DynamoDB).

```hcl
# project4-ai-chatbot/backend.tf (new)
terraform {
  backend "s3" {
    bucket       = "cloud-portfolio-tfstate-jaehwan-20260606"
    key          = "project4-ai-chatbot/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
```

## Improvements

- State is shared across machines — the `*AlreadyExists` / orphan-on-apply class of failure
  is structurally eliminated.
- Native S3 lockfile prevents two machines applying concurrently and corrupting state — no
  separate lock-table resource to provision or pay for.
- State bucket is versioned (rollback), encrypted at rest, fully private, and TLS-only.
- `bootstrap/` makes the backend infra itself reproducible IaC, reusable by P1–P3 via
  distinct `key`s under the same bucket.

## Performance Impact

none (infrastructure/state-location change; no runtime path affected). Line count: +~120
across 4 new `.tf` files (bootstrap + backend.tf), one fewer AWS resource than the initial
DynamoDB design.

## Agents Consulted

security

## Findings Addressed

none new. Security checklist verified against the state bucket: public-access-block ×4 +
SSE + TLS-only policy all present — no `[BLOCK]`/`[WARN]`.

## Findings Deferred

none. The initial design used a DynamoDB lock table; Terraform 1.15.4 deprecates the
`dynamodb_table` backend parameter, so we adopted native S3 lockfile locking
(`use_lockfile = true`) before deploying — see ADR 0002.
