# Custom Project Skills — Design Spec

**Date:** 2026-06-08
**Author:** Jaehwan
**Status:** approved

---

## Problem

The project has three `.agents/` markdown checklists (security, refactoring, idea-management)
that Claude must be explicitly reminded to consult. There is no consistent post-function quality
gate, no CI/CD check, no design sync check, and no assisted changelog writing. Work quality
depends on the user remembering to ask.

---

## Solution

Five project-local slash-command skills stored in `.claude/skills/`. Each is a standalone
`SKILL.md` — pure markdown, no build step, committed to the repo so every session picks them up.

---

## File Structure

```
.claude/
└── skills/
    ├── security/
    │   └── SKILL.md        → /security
    ├── refactoring/
    │   └── SKILL.md        → /refactoring
    ├── cicd/
    │   └── SKILL.md        → /cicd
    ├── design/
    │   └── SKILL.md        → /design
    └── changelog/
        └── SKILL.md        → /changelog
```

---

## Skill Scopes

### `/security`

**Trigger:** after any Terraform or Lambda change.

**What it checks:**
- `iam.tf` — no wildcard actions, ARNs scoped to specific resources, no `iam:PassRole` on Lambda roles
- `main.tf` — S3 buckets have `public_access_block` (all four flags) and AES256 encryption
- `lambda/*/index.py` — no hardcoded secrets, no `verify=False`, no full-event logging at INFO
- SSM usage — API keys sourced from SSM/Parameter Store, never from env vars directly in code
- `backend.tf` — remote state backend present before apply; state is non-empty for live stacks

**Output tags:** `[BLOCK]` / `[WARN]` / `[INFO]`

---

### `/refactoring`

**Trigger:** after writing or expanding a function.

**What it checks:**
- Line count > 40 in any Lambda handler — flag for extraction
- Nesting depth > 4 levels — flag for guard-clause flattening
- Broad `except:` / `except Exception:` that silently swallows failures
- Repeated patterns across 3+ Lambda packages — flag for shared-module extraction
- Business logic ordering preserved when flattening (nesting encodes rules)

**Output tags:** `[ACTION]` / `[DEFER]` / `[RESOLVED]`

---

### `/cicd`

**Trigger:** after adding a new resource, Lambda function, or project.

**Two-part check:**

**Part 1 — Terraform wiring:**
- New Lambda present in `main.tf` (function, log group, permission, trigger)
- IAM role/policy in `iam.tf` with least-privilege actions
- Input variables declared in `variables.tf`
- Useful outputs (endpoint URLs, ARNs) in `outputs.tf`
- `backend.tf` present if this is a new project

**Part 2 — GitHub Actions:**
- `.github/workflows/` covers the new component (init, plan, or deploy step)
- Workflow files reference the correct project directory
- No hardcoded credentials in workflow YAML

**Output tags:** `[MISSING]` / `[WARN]` / `[OK]`

---

### `/design`

**Trigger:** after adding a new feature, function, or project.

**Two-part check:**

**Part 1 — Doc sync:**
- `docs/design/p[N]-*/design.md` reflects the new function/resource
- Architecture diagram in design doc matches current `main.tf`
- `docs/todo.md` still describes the current plan, not a stale one
- Any superseded decisions are marked superseded, not silently absent

**Part 2 — Architecture quality:**
- Function has one clear purpose (single-responsibility)
- Naming follows P1–P5 conventions (`p[N]-`, `snake_case` for Python, `kebab-case` for resources)
- Lambda handler is thin — business logic extracted to helper functions
- New function reuses an existing pattern (P1 S3/CDN, P2 DynamoDB/TTL, P3 SNS, P4 SSM) rather than inventing a new one where a pattern already fits

**Output tags:** `[STALE]` / `[UPDATE]` / `[CONCERN]` / `[OK]`

---

### `/changelog`

**Trigger:** when ready to record a completed change.

**What it does:**
1. Reads the current diff and the work done in this session
2. Infers the changelog type (`upgrade` / `bug` / `test`) from the diff — overridden by argument
3. Writes a populated `docs/changelog/YY-MM-DD [type] Subject.md` using `docs/changelog/template.md`
4. Fills all required fields: Type, Files Changed, Why Changed, Contents Diff, Improvements, Performance Impact, Agents Consulted, Findings Addressed, Findings Deferred
5. Adds the index row to `docs/changelog/README.md`

**Command variants:**
```
/changelog              — infers type from diff
/changelog upgrade      — forces [upgrade] type
/changelog bug          — forces [bug] type
/changelog test         — forces [test] type
```

**Output:** produces files directly — no finding tags.

---

## Output Format (all skills except `/changelog`)

```
## /skill-name — YY-MM-DD

### Findings
[SEVERITY] file:line — description

### Summary
One sentence: pass / findings to address.

### Next step
Exact action: fix X in file:line, defer with justification, or no action needed.
```

---

## Recommended Invocation Order

Run after completing a new function or feature, skipping skills not relevant to the change:

```
/security  →  /refactoring  →  /cicd  →  /design  →  /changelog
```

| Change type | Skills to run |
|-------------|---------------|
| New Lambda function | all five |
| Terraform resource only | `/security` `/cicd` `/changelog` |
| Docs / design update | `/design` `/changelog` |
| Pure refactor | `/refactoring` `/changelog` |
| Bug fix | `/security` `/refactoring` `/changelog bug` |

---

## Relationship to `.agents/`

The `.agents/` files (security, refactoring, idea-management) remain the authoritative reference
for human-readable checklists. The skills are the invocable front-door. When an `.agents/` file
is updated, the corresponding skill checklist should be updated to match.

---

## Out of Scope

- Automatic hooks (token cost too high; manual invocation preferred)
- Combined `/check` skill that runs all four checks (separate skills preferred for token efficiency)
- `/changelog` auto-writing after every skill run (user controls when to write)
- P6+ project-specific extensions (add to existing skills when P6 is built)
