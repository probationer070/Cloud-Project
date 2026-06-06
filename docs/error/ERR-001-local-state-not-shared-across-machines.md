# ERR-001 — Local State Not Shared Across Machines

---

## Summary

`terraform apply` on the desktop failed with five `*AlreadyExists` errors because P4
used **local state**. The resources had been created from the laptop, but the laptop's
`terraform.tfstate` never reached the desktop, so the desktop's empty state tried to
re-create resources that already exist in the shared AWS account.

---

## Metadata

| Field | Value |
|-------|-------|
| **ID** | ERR-001 |
| **Date Discovered** | 2026-06-06 |
| **Date Resolved** | 2026-06-06 (deployed & verified on desktop; laptop cross-check pending) |
| **Severity** | `dev-only` |
| **Component** | `project4-ai-chatbot/` (no backend config — local state) |
| **Introduced In** | Initial P4 Terraform setup (local-state default, branch `Testo`) |
| **Discovered By** | `manual-test` (terraform apply on desktop) |

---

## Symptom

`terraform apply` on the desktop tried to **create** resources that already exist in
the shared AWS account, failing with five errors at once:

```
Error: creating IAM Role (p4-chatbot-chatbot-role): ... 409 EntityAlreadyExists:
       Role with name p4-chatbot-chatbot-role already exists.
Error: creating AWS DynamoDB Table (p4-chatbot-sessions): ... 400 ResourceInUseException:
       Table already exists: p4-chatbot-sessions
Error: creating CloudWatch Logs Log Group (/aws/apigateway/p4-chatbot): ... 400
       ResourceAlreadyExistsException: The specified log group already exists
Error: creating S3 Bucket (p4-chatbot-ui-jaehwan-20260528): ... 409 BucketAlreadyOwnedByYou
Error: creating CloudFront Origin Access Control (p4-chatbot-oac): ... 409
       OriginAccessControlAlreadyExists
```

Inspecting the desktop's `terraform.tfstate`:

```
resources: 0
outputs:   []
serial:    63
lineage:   42258344-0963-0dcf-fceb-1c605e30070d
```

State had been written 63 times (serial 63) yet tracked **0 resources** — the desktop
never held the real state.

---

## Root Cause

**Terraform was using local state with no remote backend.** Local state lives in
`terraform.tfstate` on a single machine's disk and is (correctly) gitignored because it
can contain secrets. Git synced the `.tf` *configuration* between laptop and desktop, but
**not the state file**.

Result: the AWS account is shared, so the resources physically exist, but the only state
that knew about them was on the laptop. The desktop's local state was empty, so Terraform
planned to create everything from scratch — and every create call collided with an
already-existing resource.

This is the canonical failure mode of local state on a multi-machine workflow. Nothing in
the code was "wrong"; the **state location** was the defect.

---

## Fix Applied

### Files Changed

| File | Change |
|------|--------|
| `bootstrap/main.tf` (new) | S3 state bucket (versioned, AES256, public-access-blocked ×4, TLS-only policy); own local state. Locking via native S3 lockfile (no DynamoDB) |
| `bootstrap/variables.tf`, `bootstrap/outputs.tf`, `bootstrap/README.md` (new) | bucket name + region; `state_bucket` output; bootstrap-first runbook |
| `project4-ai-chatbot/backend.tf` (new) | `backend "s3"` block with `use_lockfile = true`, migrating P4 to the shared remote state |
| `.agents/security.md` | pre-apply check: remote backend configured + non-empty state on a live stack |

### Code Change Summary

Permanent fix: migrate P4 from local state to an **S3 remote backend with native lockfile
locking** (`use_lockfile = true`), created by a standalone `bootstrap/` config. Laptop and
desktop now read/write the same state, and the S3 lockfile prevents concurrent applies.

```hcl
# project4-ai-chatbot/backend.tf  (created)
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

**Operator steps to complete the migration** — done 2026-06-06:
1. ✓ Laptop: `terraform destroy` the orphaned stack (used the laptop's good state).
2. ✓ Desktop: `cd bootstrap && terraform init && terraform apply` — state bucket
   `cloud-portfolio-tfstate-jaehwan-20260606` created (versioned, AES256, PAB ×4, TLS-only).
   Skipping this was the `NoSuchBucket` error (hit twice; Terraform left state unmodified each time).
3. ✓ Desktop: `terraform init -migrate-state` then `terraform apply` — 24-resource P4 stack
   rebuilt into the S3 state; `terraform plan` reports **"No changes"** (state matches reality).

> Status: RESOLVED on the desktop — P4 reads/writes shared S3 state with native lockfile,
> `plan` clean. Final cross-machine proof: laptop `terraform init` + `terraform plan` →
> "No changes" (run on next laptop session).

---

## Prevention

### What to Check in Future

- [ ] Before `terraform apply` on a machine, confirm `terraform.tfstate` tracks the
      expected resource count (`resources: N`, not `0`) — an empty state on an
      already-deployed stack means the state is missing.
- [ ] Any stack worked on from more than one machine MUST use a remote backend
      (S3 + DynamoDB lock), never local state.
- [ ] If you see a batch of `*AlreadyExists` / `ResourceInUseException` /
      `BucketAlreadyOwnedByYou` errors on `apply`, suspect state divergence first —
      do not delete resources before checking the state.
- [ ] Confirm `terraform.tfstate*` is gitignored so a stale/empty state is never synced
      between machines via git.

### Agent / Checklist Update

| Agent File | Change Made | Rationale |
|-----------|-------------|-----------|
| `.agents/security.md` | Added pre-apply check: verify remote backend configured + state non-empty before `terraform apply` | This error would have been caught by confirming a shared backend exists before applying from a second machine |

> Note: apply the above row to `.agents/security.md` when the backend fix lands.

### Test Added

N/A — infrastructure/state-location issue, not unit-testable. The mechanical guard is the
pre-apply checklist item above (remote backend configured + non-empty state) rather than a
code test.

---

## Related

- **Related errors:** none yet
- **Agent findings:** none (not flagged by an agent; found via failed apply)
- **CHANGELOG entry:** `docs/changelog/26-06-06 [upgrade] P4 S3 Remote Backend and Bootstrap.md`
- **ADR:** `docs/adr/0002-s3-remote-state-backend.md` (the architectural decision this error drove)
