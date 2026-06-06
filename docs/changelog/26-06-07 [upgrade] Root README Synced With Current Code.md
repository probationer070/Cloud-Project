# 26-06-07 [upgrade] Root README Synced With Current Code

**Type:** upgrade
**Branch / Commit:** Testo / (pending)

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `README.md` | Intro block | Added "Shared Terraform state" note: `bootstrap/` creates one S3 state bucket, P4 uses it via `backend.tf`, P1–P3 still local; links ADR-0002 |
| `README.md` | P3 diagram | "daily midnight" → "daily 09:01 KST" to match the service table and `cron(1 0 * * ? *)` (UTC 00:01) |
| `README.md` | P4 Goal + diagram + service table | Documented pluggable AI provider (Gemini default / Bedrock optional via `AI_PROVIDER`); noted SSM parameter is Terraform-managed `PLACEHOLDER` + CLI seed; added ADR-0002 link |
| `README.md` | Repository Structure | Added `bootstrap/`, `backend.tf` note, `init-all.*`, `tf-all.ps1`, `CONTRIBUTING.md` to the tree |
| `README.md` | Deployment section | Added one-time bootstrap step, P4 SSM key-seed step, and `tf-all.ps1` all-projects usage |

## Why Changed

The root `README.md` had drifted from the code on `Testo`. Three substantive gaps:
(1) the S3 remote-state backend added for P4 (`bootstrap/`, `project4-ai-chatbot/backend.tf`,
ADR-0002) was entirely undocumented — the deploy steps still implied local-state-only and
the structure tree omitted `bootstrap/`; (2) P4 was described as Gemini-only, but
`variables.tf`/`main.tf` expose `AI_PROVIDER` (gemini|bedrock) and `lambda/chatbot/index.py`
fully implements `call_bedrock` via `bedrock-runtime`; (3) the SSM row didn't reflect that
Terraform now creates the parameter as a `PLACEHOLDER` with `ignore_changes`. Minor: P3's
ASCII diagram said "daily midnight" while the daily backup actually fires at UTC 00:01 (KST 09:01),
which the table below it already stated correctly.

## Contents Diff

**`README.md` — P4 service table (Gemini row)**
```
# Before
| Gemini API (external) | Generates AI responses (HTTP timeout 25s) | On every Lambda invocation |

# After
| Gemini API / Amazon Bedrock (external) | Generates AI responses — Gemini (HTTP timeout 25s) or Bedrock/Claude via `bedrock-runtime`, selected by `AI_PROVIDER` | On every Lambda invocation |
```

**`README.md` — Deployment (added before per-project steps)**
```
# Before
## Deployment (common)
From each project directory:
terraform init / plan / apply / destroy

# After
## Deployment
One-time bootstrap (S3 state bucket) → per-project init/plan/apply/destroy
→ P4-only SSM key seed → tf-all.ps1 across all projects
```

## Improvements

- README now matches the code on disk: remote-state backend, P4 dual provider, and
  Terraform-managed SSM parameter are all documented and cross-linked to ADR-0001/0002.
- Deployment instructions are runnable in order (bootstrap first), preventing a P4
  `terraform init` failure against a missing state bucket.
- P1 and P2 service tables were audited against `main.tf` and confirmed accurate — no change needed.

## Performance Impact

none (documentation only).

## Agents Consulted

idea-management (docs sync). No Terraform/IAM/Lambda code changed, so `security` was not required.

## Findings Addressed

none

## Findings Deferred

none
