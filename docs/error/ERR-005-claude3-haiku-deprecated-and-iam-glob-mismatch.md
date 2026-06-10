# ERR-005 — Claude 3 Haiku Deprecated and IAM Glob Mismatch

---

## Summary

The P5 query API returned HTTP 500 on every request for two stacked reasons: the configured generation model `anthropic.claude-3-haiku-20240307-v1:0` was retired by the provider ("marked as Legacy"), and after upgrading to `anthropic.claude-3-5-haiku-20241022-v1:0` the Lambda IAM policy still denied it because the resource glob `anthropic.claude-3-haiku*` does not match `claude-3-5-haiku` (the `-5` falls outside the prefix).

---

## Metadata

| Field | Value |
|-------|-------|
| **ID** | ERR-005 |
| **Date Discovered** | 2026-06-10 |
| **Date Resolved** | 2026-06-10 |
| **Severity** | `dev-only` |
| **Component** | `project5-document-engine/variables.tf`, `iam.tf` |
| **Introduced In** | e47c91c (feat: Implement document ingestion and query processing with AWS services) |
| **Discovered By** | `manual-test` — query API returned 500 after the Titan dimension fix (ERR-004) unblocked the OpenSearch path |

---

## Symptom

Two distinct errors surfaced in sequence from the same `InvokeModel` call path, only after ERR-004 (Titan dimensions) and the OpenSearch index dimension mismatch were resolved so the request reached the generation step.

**Error 1 — model retired:**

```
{"error": "처리 중 오류가 발생했습니다: An error occurred (ResourceNotFoundException) when calling
the InvokeModel operation: Access denied. This Model is marked by provider as Legacy and you have
not been actively using the model in the last 30 days. Please upgrade to an active model on
Amazon Bedrock"}
```

**Error 2 — IAM denies the new model (after changing `bedrock_model_id` to Claude 3.5 Haiku):**

```
{"error": "처리 중 오류가 발생했습니다: An error occurred (AccessDeniedException) when calling the
InvokeModel operation: User: arn:aws:sts::322551983602:assumed-role/p5-doc-engine-query-role/
p5-doc-engine-query is not authorized to perform: bedrock:InvokeModel on resource:
arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-haiku-20241022-v1:0 because no
identity-based policy allows the bedrock:InvokeModel action"}
```

---

## Root Cause

**Error 1:** `anthropic.claude-3-haiku-20240307-v1:0` (Claude 3 Haiku, the March 2024 model) was hard-coded as the default `bedrock_model_id`. Anthropic/Bedrock retired it to "Legacy" status; accounts that have not invoked it in the last 30 days are blocked from calling it at all. A first-time P5 deployment has no usage history, so the very first call is denied.

**Error 2:** The IAM resource glob was written as `arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku*`. IAM `*` matches any suffix, but the literal prefix `anthropic.claude-3-haiku` is not a prefix of `anthropic.claude-3-5-haiku` — the new model inserts `-5` after `claude-3`. So the upgraded model ARN fell outside the allowed resource set and `bedrock:InvokeModel` was denied. The policy was silently tied to one specific model generation rather than to the Claude model family.

> **Update (post-incident, 2026-06-11):** AWS has since **retired the Bedrock "Model access"
> page**. Serverless foundation models auto-enable on first `InvokeModel`, and access is
> controlled by IAM/SCPs — so there was never a separate "console grant" gate for this model.
> The only residual account-level step is a possible one-time Anthropic **use-case form** for a
> first-time account. With the IAM glob fixed, the call succeeds with no console toggle.

---

## Fix Applied

### Files Changed

| File | Change |
|------|--------|
| `project5-document-engine/variables.tf` | `bedrock_model_id` default `anthropic.claude-3-haiku-20240307-v1:0` → `anthropic.claude-3-5-haiku-20241022-v1:0` |
| `project5-document-engine/iam.tf` | bedrock policy resource glob `anthropic.claude-3-haiku*` → `anthropic.claude*` |

### Code Change Summary

Upgraded the default generation model to an active (non-legacy) model, and widened the IAM resource glob to the whole Claude family so a future model-version bump does not silently break the policy again.

```hcl
# Before — variables.tf
default = "anthropic.claude-3-haiku-20240307-v1:0"
# After
default = "anthropic.claude-3-5-haiku-20241022-v1:0"
```

```hcl
# Before — iam.tf (locals.bedrock_policy.Resource)
"arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku*",
# After
"arn:aws:bedrock:*::foundation-model/anthropic.claude*",
```

---

## Prevention

### What to Check in Future

- [ ] When pinning a Bedrock model ID, confirm it is **not** marked Legacy/retired in the Bedrock console before committing it as a default
- [ ] IAM resource globs for Bedrock models should match the **family** (`anthropic.claude*`), not one dated version — version-specific prefixes break on the next model bump
- [ ] No separate Bedrock console "model access" grant is needed — that page is **retired**; serverless models auto-enable on first `InvokeModel` and access is governed by IAM. A first-time Anthropic call may still need a one-time use-case form (Bedrock console → Model catalog)
- [ ] Whenever `terraform apply` changes a Lambda env var (`bedrock_model_id`), confirm the new value's ARN is covered by the IAM policy in `iam.tf`

### Agent / Checklist Update

| Agent File | Change Made | Rationale |
|-----------|-------------|-----------|
| `.agents/security.md` | Add check: Bedrock IAM resource globs must match model family, not a single dated version | This error was an IAM-scope defect a security pass should flag |

### Test Added

No automated test — Bedrock `InvokeModel` is integration-only and the failure modes are account-state (model retirement) and IAM (resource match), neither unit-testable. Prevention is the cross-check above: model ID must be active, and its ARN must be covered by the `iam.tf` glob.

---

## Related

- **Related errors:** ERR-003 and ERR-004 (same end-to-end P5 bring-up; each masked the next once resolved — Textract blocked ingest, Titan dimensions blocked embeddings, then this blocked generation)
- **Agent findings:** none (found by manual test)
- **CHANGELOG entry:** `docs/changelog/26-06-10 [bug] P5 Claude Model Deprecation and IAM Glob Fix.md`
- **ADR:** ADR 0003 — Bedrock Claude for P5 RAG generation (over Gemini)
