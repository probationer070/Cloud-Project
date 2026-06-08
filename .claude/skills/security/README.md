# /security

**When to run:** After modifying `iam.tf`, `main.tf`, `lambda/*/index.py`, `backend.tf`, or any SSM-related code.

## What it checks

| Area | Key rules |
|------|-----------|
| `iam.tf` | No wildcard actions, scoped ARNs, no `iam:PassRole`, `p[N]-` naming |
| `main.tf` | S3 public-access-block all four flags, AES256 encryption |
| `lambda/*/index.py` | No hardcoded secrets, no `verify=False`, no full event logging |
| SSM | `WithDecryption=True`, `ignore_changes`, `/p[N]/service/key-name` convention |
| `backend.tf` | Present before first apply, unique key per project, versioning+encryption |

## Output tags

| Tag | Meaning | Action required |
|-----|---------|-----------------|
| `[BLOCK]` | Active vulnerability or secret exposure | Fix before committing — no exceptions |
| `[WARN]` | Hardening gap | Fix now, or record deferral in changelog |
| `[INFO]` | Defence-in-depth suggestion | No action required |

## Example

```
/security
```

```
## /security — 26-06-08

### Findings
[BLOCK] iam.tf:14 — Lambda role grants s3:* on Resource: "*"
[WARN]  lambda/chatbot/index.py:23 — full event dict logged at INFO level

### Summary
1 BLOCK must be fixed before commit.

### Next step
Fix iam.tf:14 — replace s3:* with s3:GetObject, s3:PutObject scoped to the bucket ARN.
```

## Tips

- Run before every `terraform apply`, not just before commits.
- A `[BLOCK]` on `iam.tf` means **stop** — do not apply until fixed.
- If a finding is intentional (e.g., `Resource: "*"` is AWS-required for a specific API), note the justification in the changelog `Findings Deferred` field.
