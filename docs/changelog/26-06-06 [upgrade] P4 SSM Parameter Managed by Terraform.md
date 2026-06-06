# 26-06-06 [upgrade] P4 SSM Parameter Managed by Terraform

**Type:** upgrade
**Branch / Commit:** Testo / (pending commit)

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project4-ai-chatbot/main.tf` | `aws_ssm_parameter.gemini` (new) | Terraform now creates the Gemini SSM parameter as a `SecureString` placeholder with `lifecycle { ignore_changes = [value] }` |
| `project4-ai-chatbot/main.tf` | `aws_lambda_function.chatbot` env | `GEMINI_API_KEY_PATH` now references `aws_ssm_parameter.gemini.name` (was a hardcoded literal) |
| `project4-ai-chatbot/README.md` | Deploy steps / teardown | Seed key **after** `apply` with `--overwrite`; `destroy` now removes the param (no manual console delete) |
| `docs/adr/0001-...md`, `docs/design/p4-ai-chatbot/design.md`, `[project] portfolio only.md`, `project4-ai-chatbot/file-structure.md` | docs | Updated to match code (Terraform-managed placeholder, not "created outside Terraform") |

## Why Changed

The SSM parameter `/cloud-portfolio/gemini-api-key` was created **manually** (`aws ssm
put-parameter`) — there was no `aws_ssm_parameter` resource in `main.tf`. Yet ADR 0001 and
`file-structure.md` both described a Terraform-provisioned placeholder, i.e. documentation
drift. User asked whether the parameter could deploy automatically. It now does: Terraform
creates it on `apply`; the operator seeds the real secret once. This realizes ADR 0001's
original design and removes the pre-apply manual step.

## Contents Diff

**`project4-ai-chatbot/main.tf`**
```hcl
# Before — no SSM resource; env var hardcoded:
GEMINI_API_KEY_PATH = "/cloud-portfolio/gemini-api-key"

# After — Terraform-managed placeholder + env var references it:
resource "aws_ssm_parameter" "gemini" {
  name  = "/cloud-portfolio/gemini-api-key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}
# ...
GEMINI_API_KEY_PATH = aws_ssm_parameter.gemini.name
```

## Improvements

- The parameter deploys automatically with the stack; the manual step shrinks to a one-time
  `put-parameter --overwrite` to seed the secret value.
- Code and docs are now consistent (ADR 0001 / file-structure.md were aspirational, now true).
- `terraform destroy` cleans up the parameter — no orphaned SSM entry to delete by hand.
- The real key still never enters Terraform state: only the literal `"PLACEHOLDER"` is stored,
  and `ignore_changes = [value]` prevents later applies from reverting the seeded key.

## Performance Impact

none (one added Terraform resource; no runtime path change). The Lambda still fetches the key
once at cold start and caches it.

## Agents Consulted

security

## Findings Addressed

none new. Security review of the new resource: `SecureString` (KMS-encrypted at rest); only a
non-secret placeholder is stored in state; `ignore_changes` keeps the real key out of state;
no new IAM actions or wildcards (`iam.tf` `ssm:GetParameter` scope unchanged).

## Findings Deferred

`[INFO]` `iam.tf` still scopes `ssm:GetParameter` via a hand-written ARN string with an
account wildcard rather than `aws_ssm_parameter.gemini.arn`. Left as-is (works, and tightening
it is out of scope for this change).
