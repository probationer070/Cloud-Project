# 26-06-11 [upgrade] P5 Bedrock Model Access Page Retired Docs

**Type:** upgrade
**Branch / Commit:** Testo / uncommitted

## Files Changed

| File | Section | What Changed |
|------|---------|--------------|
| `project5-document-engine/README.md` | Prerequisites note (#2), Step 1, Common Errors (`AccessDeniedException`) | Removed the "request/grant model access in console" instruction; replaced with auto-enable-on-first-invoke reality + one-time Anthropic use-case form; reframed `AccessDeniedException` as an IAM issue |
| `docs/plan/26-06-08 P5 Document Engine.md` | Session-2 update block, Known Blockers | Corrected the "remaining blocker = console model-access grant" to "no console grant exists; IAM governs access" |
| `docs/error/ERR-005-claude3-haiku-deprecated-and-iam-glob-mismatch.md` | Root Cause, Prevention checklist | Annotated the "third gate / console grant" claim as superseded by the page retirement |

## Why Changed

AWS retired the Bedrock **"Model access"** console page. The page now states serverless
foundation models auto-enable the first time an account calls `InvokeModel` in any commercial
region; access is controlled purely by IAM policies / SCPs; and for Anthropic models a
first-time account may need to submit a one-time use-case form. Marketplace-served models need
one invocation by a user with Marketplace permissions to enable account-wide.

The P5 docs (README Step 1, plan Known Blockers, ERR-005) all instructed the operator to "grant
model access in the console" and treated it as a hard pre-deploy gate. That step no longer
exists, so following the docs would send the operator to a retired page. It also corrects the
last-session diagnosis: the final `AccessDeniedException` was caused solely by the IAM glob
mismatch (fixed in ERR-005), not by a missing console grant — there was no such gate.

## Contents Diff

**`README.md` — Step 1 (before → after, condensed)**
```diff
-### Step 1. Enable Bedrock Model Access
-In the AWS Console (region: us-east-1), request access to both models:
-...
-> Confirm status shows "Access granted" before proceeding.
+### Step 1. Bedrock Model Access (mostly automatic now)
+AWS retired the Bedrock "Model access" page. Serverless models auto-enable on first
+InvokeModel; Titan needs nothing. Anthropic may prompt a one-time use-case form
+(Bedrock console → Model catalog). Invoke permission comes from the IAM role in iam.tf.
```

**`README.md` — Common Errors**
```diff
-→ Model access was not granted in us-east-1. Check AWS Console → Bedrock → Model access.
+→ This is an IAM problem, not a console "model access" one (that page is retired).
+  Confirm bedrock:InvokeModel on the model ARN in iam.tf.
```

**`docs/error/ERR-005` — Root Cause**
```diff
-A third gate (Bedrock console "model access" grant ...) is required before the call
-fully succeeds ...
+> Update (post-incident): AWS retired the "Model access" page. Serverless models
+> auto-enable on first InvokeModel; access is IAM/SCP-controlled — there was never a
+> separate console gate. Residual: a possible one-time Anthropic use-case form.
```

## Improvements

- Operators are no longer sent to a retired AWS console page as a required pre-deploy step.
- The real access control surface (the `iam.tf` `bedrock:InvokeModel` glob) is now the
  documented gate, matching how Bedrock actually authorizes calls.
- ERR-005's root-cause narrative is consistent with the platform's current behavior, so a
  future reader doesn't re-introduce a phantom "grant access in console" troubleshooting step.

## Performance Impact

none — documentation-only change. No code, Terraform, or IAM modified; no effect on request
latency, Lambda memory, or deploy time.

## Agents Consulted

none — documentation-only correction of an external AWS platform change. No IAM/Terraform
change, so the `security` agent (which the decision matrix maps to IAM changes) does not apply.

## Findings Addressed

none — no agent finding. Triggered by the user reporting the retired console page.

## Findings Deferred

- The `.agents/security.md` check proposed in ERR-005 ("Bedrock IAM globs must match model
  family, not a dated version") is still not applied — unchanged by this entry.
