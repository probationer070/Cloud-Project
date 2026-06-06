# ERR-002 — Terraform Destroy No-Op On Empty Remote State

---

## Summary

`terraform destroy` in `project4-ai-chatbot` reported success while destroying
**0 resources**, yet the entire P4 stack (S3, Lambda, API Gateway, CloudFront,
DynamoDB, SNS, IAM, CloudWatch) was still live and billing. The remote state was
empty, so `destroy` had nothing to act on — a silent failure that left ~11
resource groups orphaned (live in AWS, untracked by Terraform).

---

## Metadata

| Field | Value |
|-------|-------|
| **ID** | ERR-002 |
| **Date Discovered** | 2026-06-06 |
| **Date Resolved** | 2026-06-06 |
| **Severity** | `silent-failure` (also `prod-impact` — orphaned billing resources) |
| **Component** | `project4-ai-chatbot/backend.tf` (S3 remote backend) |
| **Introduced In** | branch `Testo` — backend migration (changelog `26-06-06 [upgrade] P4 S3 Remote Backend and Bootstrap`) |
| **Discovered By** | `manual-test` (user ran `terraform destroy`, observed the UI bucket survived) |

---

## Symptom

User ran `terraform destroy` expecting the P4 stack to be removed. Terraform
reported success but deleted nothing, while `p4-chatbot-ui-jaehwan-20260606` and
every other P4 resource remained visible in the AWS console.

```
# terraform destroy
Destroy complete! Resources: 0 destroyed.

# but live in AWS:
S3      p4-chatbot-ui-jaehwan-20260606      EXISTS
Lambda  p4-chatbot-chatbot                  EXISTS
APIGW   p4-chatbot-api (zwjpokvf9f)         EXISTS
CF      ESZEJ9Q0EI1SE                       Deployed
... (DynamoDB, SNS, IAM role, 2 alarms, dashboard, 2 log groups, OAC)

# terraform state list
(empty)            # exit 0, zero resources tracked
```

---

## Root Cause

`terraform destroy` acts on the **state file**, not on live AWS. It destroys only
what state records; it does not scan the account for resources to remove.

The P4 resources were originally created under **local** state. When P4 migrated
to the S3 remote backend (`backend.tf`), the existing local state was never copied
into the new backend — `terraform init` was run without migrating state (the
"copy existing state to the new backend?" step did not happen), and the local
`terraform.tfstate` ended up emptied (0 bytes) while a stale `terraform.tfstate.backup`
(15 KB) retained the old snapshot.

Result: the remote state at
`cloud-portfolio-tfstate-jaehwan-20260606/project4-ai-chatbot/terraform.tfstate`
was empty. `terraform plan` would have tried to **create** everything; `terraform
destroy` found nothing to destroy and exited cleanly. Both outcomes are silent and
dangerous: the operator believes the stack is managed (or gone) when it is neither.

Same family as **ERR-001** (local state not shared across machines) — both stem
from state not being carried correctly through the local→S3 backend migration.

---

## Fix Applied

### Files Changed

| File | Change |
|------|--------|
| _(none)_ | No source change. Root cause is operational state, not code. |

### Code Change Summary

There is no code fix. The deployed stack was already orphaned, so recovery was
operational, not a code edit:

1. Confirmed the empty state (`terraform state list` → empty, exit 0) and the
   stale backup (`terraform.tfstate.backup`, 15 KB).
2. Enumerated every live P4 resource directly via the AWS CLI by name/tag
   (`p4-chatbot-*`, suffix `jaehwan-20260606`).
3. Deleted all of them directly, respecting dependency order — CloudFront was
   disabled first, allowed to reach `Deployed`, then deleted, followed by its OAC;
   S3 emptied + removed; API Gateway, Lambda, DynamoDB, SNS, IAM role + inline
   policy, 2 CloudWatch alarms, dashboard, and 2 log groups removed.
4. Verified absence with a re-enumeration sweep (all `GONE` / `None`).

Deliberately **not** deleted: the shared SSM parameter
`/cloud-portfolio/gemini-api-key` (only referenced by P4, owned at the
`/cloud-portfolio/` scope) and the state bucket
`cloud-portfolio-tfstate-jaehwan-20260606` (the backend itself, from `bootstrap/`).

**Correct long-term remedy** (for any future backend change): re-init with
`terraform init -migrate-state`, or `terraform import` each resource into the new
backend before running `plan`/`destroy`.

---

## Prevention

### What to Check in Future

- [ ] After any backend block change or `terraform init`, run `terraform state list`
      and confirm it is **non-empty** before trusting `plan` or `destroy`.
- [ ] Never trust a `Destroy complete! Resources: 0 destroyed.` result when you know
      resources were deployed — 0 destroyed against a known-live stack means empty
      state, not a clean account.
- [ ] When migrating local → remote backend, explicitly answer "yes" to the
      "copy existing state to the new backend?" prompt, or use `-migrate-state`,
      then diff `state list` before and after to confirm the resources carried over.
- [ ] Treat a 0-byte `terraform.tfstate` plus a large `terraform.tfstate.backup` as
      a red flag that a migration silently dropped state.

### Agent / Checklist Update

| Agent File | Change Made | Rationale |
|-----------|-------------|-----------|
| `.agents/security.md` | Add a state-integrity check: verify `terraform state list` is non-empty after any backend change before apply/destroy | A destroy no-op leaves orphaned resources (live attack surface + cost) the operator believes are gone |

### Test Added

N/A — infrastructure/state behavior, not unit-testable. Covered by the manual
checklist above (state-list non-empty assertion after backend changes).

---

## Related

- **Related errors:** ERR-001 (local state not shared across machines) — same
  backend-migration root cause.
- **Agent findings:** none — discovered by manual test, not an agent run.
- **CHANGELOG entry:** `26-06-06 [bug] P4 Full Teardown And Empty State Noop`
