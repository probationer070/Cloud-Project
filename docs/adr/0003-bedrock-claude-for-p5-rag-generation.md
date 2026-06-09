# ADR 0003 — Bedrock Claude for P5 RAG Generation (over Gemini)

**Date:** 2026-06-10
**Status:** Accepted

## Context

P5 (Intelligent Document Analysis Engine) is a RAG pipeline: documents are chunked,
embedded with **Bedrock Titan Embeddings V2**, stored in OpenSearch as kNN vectors, and a
question's top-k chunks are passed to a generation model that writes the grounded answer.

The embedding side is firmly on Bedrock — the OpenSearch index is built around Titan V2's
1024-dimensional vectors (see ERR-004), so the embedder cannot move without rebuilding the
index. Only the **answer-generation** step was in question.

During first end-to-end bring-up the generation step failed repeatedly on Bedrock:
the default model `anthropic.claude-3-haiku-20240307-v1:0` was retired to "Legacy" and
refused new calls, and after upgrading, a too-narrow IAM resource glob denied the new model
(both captured in ERR-005). P4 (AI Chatbot) already calls the **Gemini API** successfully
from the same AWS account with the same Lambda pattern and a free tier, so pivoting P5's
generation step to Gemini was a real option to unblock quickly.

The question, raised in an `/office-hours` session: keep fighting Bedrock model access, or
swap generation to Gemini to ship faster?

## Decision

**Keep answer generation on Amazon Bedrock (Claude), do not pivot to Gemini.**

- **Generation model:** `anthropic.claude-3-5-haiku-20241022-v1:0` — an active
  (non-legacy) model, replacing the retired Claude 3 Haiku.
- **IAM scope:** the Lambda Bedrock policy allows the Claude **family**
  (`arn:aws:bedrock:*::foundation-model/anthropic.claude*`) rather than one dated version,
  so a future model bump does not silently break the policy.
- **Embeddings:** unchanged — Bedrock Titan Embeddings V2 at 1024 dimensions.

The deciding factor is **portfolio differentiation**: P4 already demonstrates a Gemini-based
chatbot. Keeping P5 on Bedrock + OpenSearch makes it a distinct AWS-native RAG stack rather
than "P4 with a search layer." This is a learning/portfolio project where showing Bedrock
and OpenSearch depth is the point, so the extra friction of Bedrock's access gates is
accepted as the cost of that demonstration.

## Alternatives Considered

**Pivot generation to the Gemini API (as in P4)** — already working in this account, free
tier, no Bedrock model-access gate. Rejected: it makes P5's AI provider identical to P4,
erasing the differentiation that justifies P5 as a separate portfolio piece. It would also
add a cross-service call out of AWS for the generation step while embeddings stay on Bedrock,
splitting the pipeline across two providers for no architectural benefit.

**Keep Claude 3 Haiku and rely on prior usage to avoid the Legacy block** — zero change.
Rejected: the model is retired; a fresh deployment has no 30-day usage history, so the first
call is always denied. Not a stable foundation.

**Use a larger Claude model (e.g. Sonnet) for generation** — higher answer quality.
Rejected for now: Haiku is the cost-appropriate choice for a short RAG answer over a handful
of chunks, and OpenSearch is already the cost driver (~$0.86/day). Revisit only if answer
quality proves insufficient.

## Consequences

- P5 stays a single-vendor (Bedrock) AI pipeline for both embedding and generation, all in
  `us-east-1` — simpler to reason about and a cleaner portfolio story than a split stack.
- Two operational gates must be satisfied before generation works, and they are easy to
  confuse (both can surface as "access denied"): (1) IAM `bedrock:InvokeModel` on the model
  ARN, and (2) Bedrock console **model access** consent for that model in `us-east-1`. The
  README Step 1 and ERR-005 Prevention both call this out.
- The family-wide IAM glob (`anthropic.claude*`) trades a small amount of least-privilege
  precision for resilience against model-version bumps; acceptable because the action is
  limited to `InvokeModel` on read-only foundation models.
- Bedrock model retirement is now a known maintenance risk: a pinned model ID can become
  Legacy over time and must be checked when revisiting P5.

## Related

- ERR-005 — Claude 3 Haiku deprecated and IAM glob mismatch (the failure that prompted this decision)
- ERR-004 — Titan V2 invalid dimension (why the embedder is pinned to Bedrock/1024-dim)
- CHANGELOG: `docs/changelog/26-06-10 [bug] P5 Claude Model Deprecation and IAM Glob Fix.md`
- `docs/plan/26-06-08 P5 Document Engine.md` — P5 bring-up and validation plan
