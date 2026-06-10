# ERR-006 — kNN 400 (float mapping), Inference-Profile Requirement, and Model Entitlement

---

## Summary

First fully successful P5 end-to-end query bring-up surfaced three stacked failures from the
query path, each masked by the one before it:

1. **OpenSearch kNN search returned HTTP 400** because the `documents` index had `embedding`
   mapped as `float`, not `knn_vector` — the Ingest Lambda wrote documents *before* the index
   was explicitly created, so OpenSearch auto-created it with a dynamic (wrong) mapping.
2. **Bedrock rejected the on-demand model ID** — `anthropic.claude-3-5-haiku-20241022-v1:0`
   cannot be invoked by its bare foundation-model ID; Claude 3.5+ requires an **inference
   profile** (`us.anthropic.claude-...`).
3. **Model entitlement** — after switching to inference profiles, Claude 3.x Haiku is "Legacy"
   and Claude 4.x Haiku/Sonnet require an **AWS Marketplace subscription** (which neither the
   Lambda role nor the developer's IAM identity is authorized to perform). Only
   `us.anthropic.claude-opus-4-5-20251101-v1:0` was already entitled in this account and worked.

---

## Metadata

| Field | Value |
|-------|-------|
| **ID** | ERR-006 |
| **Date Discovered** | 2026-06-11 |
| **Date Resolved** | 2026-06-11 |
| **Severity** | `dev-only` (blocked all query responses; no data loss) |
| **Component** | `project5-document-engine/lambda/query/index.py` (search + generate), `variables.tf`, `iam.tf`, OpenSearch index `documents` |
| **Introduced In** | e47c91c (initial P5 implementation) + operational (index created after first ingest) |
| **Discovered By** | `manual-test` — live query API validation after ERR-005 fixes were deployed |

---

## Symptom

**Error 1 — kNN search 400:**
```
{"error": "처리 중 오류가 발생했습니다: HTTP Error 400: Bad Request"}
```
The query Lambda's catch-all (`index.py` line 83) wrapped a `urllib.error.HTTPError` raised by
`_opensearch_request` on the `_search` call. The OpenSearch error body (the actual reason) is
lost because `urllib` raises before the body is read, so logs only showed "400".

`GET /documents/_mapping` revealed the cause:
```json
"embedding": { "type": "float" }   // expected: "type": "knn_vector", "dimension": 1024
```
plus `doc_id`/`source_key`/`text` all mapped as `text` (dynamic defaults) — proof the index
was auto-created by an indexing write, not by the explicit Step 4 `PUT`.

**Error 2 — on-demand model not supported:**
```
ValidationException ... Invocation of model ID anthropic.claude-3-5-haiku-20241022-v1:0 with
on-demand throughput isn't supported. Retry your request with the ID or ARN of an inference
profile that contains this model.
```

**Error 3 — model entitlement (two forms):**
```
ResourceNotFoundException ... This Model is marked by provider as Legacy and you have not been
actively using the model in the last 30 days.                      (Claude 3.x)

AccessDeniedException ... not authorized to perform the required AWS Marketplace actions
(aws-marketplace:ViewSubscriptions, aws-marketplace:Subscribe) to enable access to this model.
                                                                    (Claude 4.x Haiku/Sonnet)
```

---

## Root Cause

**Error 1 — index auto-creation order.** OpenSearch auto-creates a missing index on first write
using dynamic mapping. If the Ingest Lambda indexes a chunk before `PUT /documents` runs with
the explicit knn mapping, `embedding` becomes a plain `float` array. A `knn` query against a
non-`knn_vector` field is rejected with 400. The README ordering (create index → then upload)
is correct; the live index had been populated out of order in a prior run.

**Error 2 — inference profile required.** Anthropic models from Claude 3.5 onward on Bedrock are
not invocable via the bare `foundation-model/<id>` on-demand path; they must be called through a
cross-region **inference profile** whose ID is region-prefixed (`us.` / `global.`). The query
Lambda passed the raw model ID from `bedrock_model_id`, so `InvokeModel` raised
`ValidationException`.

**Error 3 — account entitlement, not code.** Claude 3.x models are retired (Legacy) for an
account with no recent usage. Claude 4.x Haiku/Sonnet are served via AWS Marketplace and require
a one-time subscription performed by a principal holding `aws-marketplace:Subscribe` /
`ViewSubscriptions`. Neither the Lambda execution role nor the developer's CLI identity holds
those permissions, so those models stayed denied. A direct-invoke probe across candidates showed
`us.anthropic.claude-opus-4-5-20251101-v1:0` was the only Anthropic model already entitled in the
account; it returned a valid completion.

---

## Fix Applied

### Files Changed

| File | Change |
|------|--------|
| OpenSearch index `documents` | Deleted and recreated with the explicit `knn_vector` (1024-dim, hnsw/nmslib/cosinesimil) mapping, then re-ingested the sample PDF so chunks land under the correct mapping |
| `project5-document-engine/variables.tf` | `bedrock_model_id` → inference profile; settled on `us.anthropic.claude-opus-4-5-20251101-v1:0` (only entitled Anthropic model in this account) |
| `project5-document-engine/iam.tf` | Added `arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude*` to the shared `bedrock_policy` so `InvokeModel` is allowed on the inference-profile ARN (the foundation-model glob already covered the cross-region underlying models) |

### Verification

```
POST /query {"question":"What was the Q4 revenue?"}
→ 200 {"answer":"Q4 revenue ... $2,000,000 ... 35% growth ...","sources":["sample.pdf"],"chunks_used":1}
```
Matches the README Step 7 expected output. (A follow-up call briefly returned "Marketplace
subscription still being processed — try again after 15 minutes"; the Opus 4.5 entitlement was
still propagating, not a code fault.)

---

## Prevention

### What to Check in Future

- [ ] **Create the OpenSearch index before the first document is ingested.** If `_mapping` shows
      `embedding` as `float` (not `knn_vector`), the index was auto-created out of order — delete
      and recreate it with the explicit mapping, then re-ingest. Consider having Terraform create
      the index as part of `apply` so the ordering can't go wrong.
- [ ] Bedrock generation models from Claude 3.5+ must be referenced by an **inference profile ID**
      (`us.` / `global.` prefix), never the bare foundation-model ID — the on-demand path returns
      `ValidationException`.
- [ ] Before pinning a `bedrock_model_id`, confirm the account is actually **entitled** to it:
      3.x models may be Legacy; 4.x Haiku/Sonnet may need an AWS Marketplace subscription done by
      an admin. Probe with `aws bedrock-runtime invoke-model` before wiring it into the Lambda.
- [ ] IAM for inference profiles needs `bedrock:InvokeModel` on **both** the `inference-profile/`
      ARN and the underlying cross-region `foundation-model/` ARNs.

### Agent / Checklist Update

| Agent File | Change Made | Rationale |
|-----------|-------------|-----------|
| `.agents/security.md` | (proposed) Bedrock IAM must allow `InvokeModel` on the inference-profile ARN, not only the foundation-model ARN, for Claude 3.5+ | A security pass reviewing the Bedrock policy should catch a profile/foundation-model ARN mismatch |

### Test Added

No automated test — all three failure modes are integration-only (OpenSearch index state, Bedrock
inference-profile semantics, account entitlement). Prevention is the cross-checks above.

---

## Related

- **ERR-005** — Claude 3 Haiku Legacy + IAM glob mismatch (immediately preceding fix; this record
  is the next layer uncovered once ERR-005's changes deployed)
- **ERR-004** — Titan V2 1024-dim (why the index mapping must be `knn_vector` dimension 1024)
- **ADR 0003** — Bedrock Claude for P5 generation (model choice; amended for the entitlement reality)
- **CHANGELOG:** `docs/changelog/26-06-11 [bug] P5 Inference Profile and Model Entitlement Fix.md`
