# 26-06-11 [upgrade] P5 Default Model Switched to Haiku 4.5 for Cost Efficiency

**Type:** upgrade
**Branch / Commit:** Testo / (uncommitted)

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project5-document-engine/variables.tf` | `bedrock_model_id` | Default switched from Opus 4.5 to Haiku 4.5; description rewritten with Free Tier cost rationale + Opus fallback |
| `project5-document-engine/README.md` | Cost table, Step 1, Common Errors (×2) | Documented Haiku 4.5 as the default (cost-efficient) with Opus 4.5 as the fallback when the Marketplace subscription isn't active |
| `docs/plan/26-06-08 P5 Document Engine.md` | Session-4 block, Net summary, Known Blockers | Recorded the switch as done; reframed cost-efficiency rules |
| `docs/adr/0003-bedrock-claude-for-p5-rag-generation.md` | Amendment | Updated stated generation model to Haiku 4.5 (Opus fallback) |

## Why Changed

Every project in this repo runs on a **Free Tier AWS account**, and the user explicitly called
out cost efficiency as a priority. Bedrock is never in the Free Tier (per-token billing), so the
generation model is P5's main controllable cost. The default was `us.anthropic.claude-opus-4-5`
(~$5/$25 per 1M in/out) — the *most expensive* Anthropic model — chosen during bring-up only
because it was the sole entitled model at the time (ERR-006). Defaulting a cost-sensitive project
to the priciest model is the wrong choice; Haiku 4.5 (~$1/$5 per 1M) is ~5× cheaper for the same
short RAG answers.

## Contents Diff

**`project5-document-engine/variables.tf` — `bedrock_model_id`**
```hcl
# Before
default     = "us.anthropic.claude-opus-4-5-20251101-v1:0"

# After
default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
```

## Improvements

- Generation cost dropped ~5× per query (Haiku 4.5 vs Opus 4.5), aligning P5 with the Free Tier
  premise.
- Default, README, plan, and ADR-0003 now agree on the model (was drifting: Opus in docs vs the
  documented intent to use Haiku).
- Fallback path made explicit everywhere: if the Claude Haiku 4.5 Marketplace subscription isn't
  active, generation returns AccessDenied / "subscription required" → revert to Opus 4.5.

## Performance Impact

Generation cost ~5× lower (Opus 4.5 ~$5/$25 → Haiku 4.5 ~$1/$5 per 1M input/output tokens).
Latency: Haiku is typically faster than Opus for short answers (not separately benchmarked).
No change to embeddings, indexing, or OpenSearch cost.

## Agents Consulted

security (self-check)

## Findings Addressed

none

## Findings Deferred

- **[INFO] Default now depends on external Marketplace-subscription state.** If the Haiku 4.5
  subscription is not active in the account, `terraform apply` succeeds but the first query fails
  at invoke time. This is operational, not a security/IAM gap — `iam.tf` already authorizes the
  Claude family (`inference-profile/us.anthropic.claude*` + `foundation-model/anthropic.claude*`),
  so no IAM change was needed. Fallback to Opus 4.5 is documented in variables.tf, README Step 1,
  and the plan.
