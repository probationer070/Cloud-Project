# Error Record Index — Smart Vault

Every bug that reaches a running system (local, dev, or prod) gets a record here.
The goal is not blame — it is **preventing the same class of bug from recurring**.

Records are written after the fix is confirmed. They answer three questions:
1. What happened and why?
2. How was it fixed?
3. What prevents it from happening again?

---

## How to Create a Record

1. Copy `template.md` to a new file named `ERR-NNN-short-description.md`
   - Increment `NNN` from the last entry in the index below
   - Keep the short description to 3–5 words, kebab-cased
2. Fill in all fields — leave none blank (write "N/A" only if genuinely not applicable)
3. Add a one-line entry to the index table below
4. Add a CHANGELOG entry in `docs/CHANGELOG.md`

**When to write a record:**
- A bug caused incorrect behavior in any environment (local, dev, or prod)
- A silent failure was discovered (wrong output, wrong data, no error raised)
- A test caught a regression introduced by a code change
- An agent finding (BLOCK/WARN) revealed an existing defect in running code

**When NOT to write a record:**
- Type errors or syntax errors caught before any execution
- Failing tests that were never passing (expected failures during development)
- Configuration mistakes with no code change required

---

## Error Index

| ID | Date | Component | Summary | Status |
|----|------|-----------|---------|--------|
| [ERR-001](ERR-001-local-state-not-shared-across-machines.md) | 2026-06-06 | `project4-ai-chatbot/` (local state) | `apply` on desktop hit 5 `*AlreadyExists` errors — local state never synced from laptop; fixed with S3 remote backend + `bootstrap/` | Resolved (laptop cross-check pending) |
| [ERR-002](ERR-002-terraform-destroy-noop-empty-state.md) | 2026-06-06 | `project4-ai-chatbot/backend.tf` (S3 backend) | `terraform destroy` reported `0 destroyed` while the full P4 stack stayed live — remote state was empty after the backend migration never carried state over; stack torn down manually via AWS CLI | Resolved |
| [ERR-003](ERR-003-textract-subscription-required-ap-northeast-2.md) | 2026-06-09 | `project5-document-engine/variables.tf` | Ingest Lambda failed with `SubscriptionRequiredException` — Textract in `ap-northeast-2` requires a service subscription the account does not have; fixed by changing `aws_region` to `us-east-1` | Resolved |
| [ERR-004](ERR-004-titan-v2-invalid-dimension-1536.md) | 2026-06-09 | `lambda/ingest/index.py`, `lambda/query/index.py`, `outputs.tf` | Titan Embeddings V2 rejected `"dimensions": 1536` — V2 max is 1024; V1 is the source of the 1536 value; fixed all three occurrences to 1024 | Resolved |
| [ERR-005](ERR-005-claude3-haiku-deprecated-and-iam-glob-mismatch.md) | 2026-06-10 | `project5-document-engine/variables.tf`, `iam.tf` | Query API 500: Claude 3 Haiku retired as Legacy, and after upgrade the IAM glob `anthropic.claude-3-haiku*` failed to match `claude-3-5-haiku`; fixed model ID to 3.5 Haiku and widened glob to `anthropic.claude*` | Resolved (console model-access grant still required) |
