# 26-06-11 [bug] P5 Inference Profile and Model Entitlement Fix

**Type:** bug
**Branch / Commit:** Testo / uncommitted

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project5-document-engine/variables.tf` | `bedrock_model_id` | default → `us.anthropic.claude-opus-4-5-20251101-v1:0` (inference profile; only Anthropic model entitled in this account) |
| `project5-document-engine/iam.tf` | `locals.bedrock_policy` | added `arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude*` to the `InvokeModel` resource list |
| OpenSearch index `documents` | — | deleted + recreated with explicit `knn_vector` (1024-dim) mapping; re-ingested the canonical Q4 sample PDF so chunks land under the correct mapping |
| `project5-document-engine/index-mapping.json` | (new) | helper file holding the index mapping JSON for clean recreate on Windows (avoids PowerShell/curl quoting issues) |

## Why Changed

Live end-to-end query validation (the open Goal 3 from the P5 plan) failed three times in
sequence, each failure masked by the previous one:

1. **OpenSearch kNN search returned HTTP 400.** `GET /documents/_mapping` showed `embedding`
   mapped as `float`, not `knn_vector` — the Ingest Lambda had written documents before the
   index was explicitly created, so OpenSearch auto-created it with dynamic mapping. A `knn`
   query against a non-`knn_vector` field is rejected with 400.
2. **`ValidationException`: on-demand model ID not supported.** Claude 3.5+ on Bedrock cannot be
   invoked by its bare `foundation-model` ID; it requires a cross-region **inference profile**
   (`us.anthropic.claude-...`).
3. **Model entitlement.** With inference profiles, Claude 3.x is Legacy ("not used in 30 days")
   and Claude 4.x Haiku/Sonnet require an **AWS Marketplace subscription** that neither the
   Lambda role nor the developer identity can perform. A direct-invoke probe found
   `us.anthropic.claude-opus-4-5-20251101-v1:0` was the only entitled Anthropic model.

Full analysis in ERR-006. This supersedes the assumption (ERR-005 / earlier 26-06-11 doc entry)
that a console "model access" grant was the last gate — the real gate is inference-profile
referencing plus account entitlement.

## Contents Diff

**`variables.tf` — `bedrock_model_id`**
```hcl
# Before (ERR-005 state)
default = "anthropic.claude-3-5-haiku-20241022-v1:0"
# After
default = "us.anthropic.claude-opus-4-5-20251101-v1:0"
```

**`iam.tf` — `locals.bedrock_policy.Resource`**
```hcl
 Resource = [
   "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0",
   "arn:aws:bedrock:*::foundation-model/anthropic.claude*",
+  "arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude*",
 ]
```

## Improvements

- The query API now returns a grounded answer end-to-end: `"What was the Q4 revenue?"` →
  `"$2,000,000 ... 35% growth"` + `sources: ["sample.pdf"]`, matching README Step 7.
- `bedrock_model_id` is now an inference-profile ID, the only form Bedrock accepts for current
  Anthropic models — a fresh deploy no longer fails with `ValidationException`.
- IAM allows `InvokeModel` on the inference-profile ARN as well as the underlying foundation
  models, so the profile-based call is actually authorized.
- The OpenSearch index now has the correct `knn_vector` mapping; the recreate is captured in a
  reusable `index-mapping.json` for Windows operators.

## Performance Impact

Latency: Opus 4.5 is a larger model than the originally intended Haiku, so per-query generation
latency and cost are higher (Opus pricing ≫ Haiku). Acceptable for the test/portfolio scope
(handful of queries, stack destroyed after). README documents switching to Haiku 4.5 once an
admin completes the Marketplace subscription. No change to embedding or search latency.

## Agents Consulted

`security` (checklist self-run, not a spawned agent) — `iam.tf` change reviewed:
action remains `bedrock:InvokeModel` only (no wildcard action), scoped to Claude inference
profiles + read-only foundation models, no `PassRole`/secrets. One **[INFO]**: the
`inference-profile/` ARN uses `*` for the account-id segment; could be pinned to the account ID
for tighter least-privilege, but matches the existing glob style and is invoke-only — deferred.

## Findings Addressed

- ERR-006 / Error 1: kNN 400 from `float` mapping — index recreated as `knn_vector`
- ERR-006 / Error 2: on-demand model rejected — switched to inference-profile ID
- ERR-006 / Error 3: model entitlement — switched to the entitled Opus 4.5 model + IAM for profile ARN

## Findings Deferred

- **[INFO]** Pin the inference-profile ARN to the account ID instead of `*` — minor least-privilege hardening, not done.
- **Cost:** default is Opus 4.5 (expensive) because it is the only entitled Anthropic model. Switching to the cheaper Haiku 4.5 requires an account admin to complete the AWS Marketplace subscription — an account action, not a code change.
- **Robustness:** the index-ordering trap (ingest before index creation → `float` mapping) is currently prevented only by following the README order; automating index creation in `terraform apply` is proposed in ERR-006 but not implemented.
- `.agents/security.md` checks proposed in ERR-005 and ERR-006 are still not applied.
