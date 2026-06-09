# 26-06-10 [bug] P5 Claude Model Deprecation and IAM Glob Fix

**Type:** bug
**Branch / Commit:** Testo / uncommitted

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project5-document-engine/variables.tf` | `bedrock_model_id` | default `anthropic.claude-3-haiku-20240307-v1:0` → `anthropic.claude-3-5-haiku-20241022-v1:0` |
| `project5-document-engine/iam.tf` | `locals.bedrock_policy` | resource glob `anthropic.claude-3-haiku*` → `anthropic.claude*` |
| `project5-document-engine/README.md` | Step 1 / Step 7 | model name updated to Claude 3.5 Haiku; Step 7 PowerShell query switched from `curl.exe` (broken quoting) to `Invoke-RestMethod` |
| `docs/plan/26-06-08 P5 Document Engine.md` | Step 3 index-create command | region `ap-northeast-2` → `us-east-1`, index `dimension` `1536` → `1024` |

## Why Changed

During first end-to-end P5 bring-up, the query API returned HTTP 500 on every request once
the OpenSearch path was unblocked (after ERR-004). Two stacked Bedrock failures surfaced
from the generation step:

1. **Model retired (`ResourceNotFoundException`):** `anthropic.claude-3-haiku-20240307-v1:0`
   is marked Legacy by the provider; an account with no usage in the last 30 days is blocked
   from calling it. A fresh deploy is always denied.
2. **IAM denies the upgraded model (`AccessDeniedException`):** after changing the model to
   Claude 3.5 Haiku, the Lambda policy still denied `bedrock:InvokeModel` because the glob
   `anthropic.claude-3-haiku*` is not a prefix of `anthropic.claude-3-5-haiku` (the `-5`
   breaks the match). The policy was pinned to one model generation rather than the family.

The plan doc's Step 3 also still carried the pre-ERR-004 values (`ap-northeast-2`, dimension
`1536`); leaving the OpenSearch index at 1536 while the Lambda embeds at 1024 caused a kNN
dimension-mismatch 400, so the stale plan command was corrected to match the fixed code.

Full root-cause analysis in ERR-005. Decision to stay on Bedrock (vs. pivoting generation to
Gemini) recorded in ADR 0003.

## Contents Diff

**`variables.tf` — `bedrock_model_id`**
```hcl
# Before
default = "anthropic.claude-3-haiku-20240307-v1:0"

# After
default = "anthropic.claude-3-5-haiku-20241022-v1:0"
```

**`iam.tf` — `locals.bedrock_policy.Resource`**
```hcl
# Before
Resource = [
  "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0",
  "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku*",
]

# After
Resource = [
  "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0",
  "arn:aws:bedrock:*::foundation-model/anthropic.claude*",
]
```

**`docs/plan/26-06-08 P5 Document Engine.md` — Step 3 index-create command**
```diff
- $REGION   = "ap-northeast-2"
+ $REGION   = "us-east-1"
- ...\"dimension\":1536,...
+ ...\"dimension\":1024,...
```

## Improvements

- P5 generation now targets an active (non-legacy) model, so a first-time deploy succeeds
  instead of being blocked by the 30-day-usage retirement rule.
- IAM glob widened to the Claude family — a future model-version bump (e.g. next Haiku) no
  longer silently breaks `bedrock:InvokeModel` the way the `-5` insertion did.
- Plan doc Step 3 is now consistent with the shipped code (1024-dim, `us-east-1`), so
  following it no longer recreates the index with a mismatched dimension.
- README Step 7 PowerShell example no longer uses `curl.exe` with single-quoted JSON
  (PowerShell strips the quotes and curl brace-globs the body) — `Invoke-RestMethod` passes
  the body intact.

## Performance Impact

none — model-ID, IAM-scope, and documentation changes only; no change to request latency or
Lambda memory. Claude 3.5 Haiku has comparable latency to Claude 3 Haiku for short RAG
answers.

## Agents Consulted

none (runtime failures found by manual test; office-hours used for the Bedrock-vs-Gemini
decision recorded in ADR 0003). A `.agents/security.md` checklist addition is proposed in
ERR-005 Prevention but not yet applied.

## Findings Addressed

- ERR-005: Claude 3 Haiku Legacy block — fixed in `variables.tf`
- ERR-005: IAM glob mismatch on `claude-3-5-haiku` — fixed in `iam.tf`

## Findings Deferred

- Bedrock console **model access** grant for Claude 3.5 Haiku in `us-east-1` is still
  required for the call to fully succeed — this is an account/console action, not a code
  change, and cannot be committed. Documented in README Step 1 and ERR-005 Prevention.
- `.agents/security.md` check for "Bedrock IAM globs must match model family, not a dated
  version" proposed in ERR-005 but not yet added.
