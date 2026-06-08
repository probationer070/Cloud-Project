# Custom Project Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create 5 project-local slash-command skills (`/security`, `/refactoring`, `/cicd`, `/design`, `/changelog`) as standalone `SKILL.md` files so any session can invoke quality gates after writing a new function.

**Architecture:** Each skill is a single pure-markdown `SKILL.md` under `.claude/skills/<name>/`. No build step, no code. Files are committed to the repo so they are available in every session automatically. Each skill is self-contained with project-specific context baked in.

**Tech Stack:** Markdown only. Claude Code skill system (project-local `.claude/skills/`).

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `.claude/skills/security/SKILL.md` | Create | `/security` slash command |
| `.claude/skills/refactoring/SKILL.md` | Create | `/refactoring` slash command |
| `.claude/skills/cicd/SKILL.md` | Create | `/cicd` slash command |
| `.claude/skills/design/SKILL.md` | Create | `/design` slash command |
| `.claude/skills/changelog/SKILL.md` | Create | `/changelog` slash command |
| `.claude/CLAUDE.md` | Modify | Add skills to Section 5 decision matrix |

---

### Task 1: Write `/security` skill

**Files:**
- Create: `.claude/skills/security/SKILL.md`

- [ ] **Step 1: Create the file with the full content below**

Write `.claude/skills/security/SKILL.md`:

```markdown
# Security Review

Run after any Terraform or Lambda change to catch IAM over-privilege, secret exposure,
missing encryption, and backend gaps before committing.

## How to use

Type `/security` after modifying any of: `iam.tf`, `main.tf`, `lambda/*/index.py`,
`backend.tf`, or any SSM-related code.

## Steps

1. Read the current diff (`git diff HEAD`) and identify which files changed.
2. For each changed file, run the relevant checklist section below.
3. Report all findings using the output format at the bottom.

## Checklist

### `iam.tf` — IAM roles and policies
- [ ] No wildcard actions (`s3:*`, `ec2:*`, `lambda:*`) — list only the actions each role needs
- [ ] Resource ARNs scoped to specific resources — `Resource: "*"` only where the AWS API requires it
- [ ] No `iam:PassRole` or `sts:AssumeRole` granted to Lambda roles
- [ ] Policy names follow `p[N]-` prefix convention (e.g., `p4-chatbot-policy`)

### `main.tf` — Infrastructure resources
- [ ] Every S3 bucket has `aws_s3_bucket_public_access_block` with all four flags `true`
- [ ] Every S3 bucket has `aws_s3_bucket_server_side_encryption_configuration` with `AES256`
- [ ] API Gateway routes do not expose internal resource ARNs in responses
- [ ] Lambda timeouts are set appropriately (Ingest ≤ 300s, Query ≤ 60s, Chatbot ≤ 30s)

### `lambda/*/index.py` — Lambda function code
- [ ] No secrets or API keys hardcoded — all sourced from `os.environ` via SSM/Parameter Store
- [ ] No `verify=False` on boto3 clients or requests calls
- [ ] No full event payload logged at INFO level — log only safe fields (session_id, doc_id, status)
- [ ] Input from request body validated before being passed to any AWS API call

### SSM / Parameter Store usage
- [ ] API keys fetched via `ssm.get_parameter(Name=..., WithDecryption=True)`
- [ ] SSM parameter created by Terraform with `ignore_changes = [value]` — seeded separately via CLI
- [ ] Parameter name follows `/p[N]/service/key-name` convention

### `backend.tf` — Remote state
- [ ] `backend.tf` present in any new project directory before first `terraform apply`
- [ ] Points to the bootstrap S3 bucket with a unique `key` per project (e.g., `p5/terraform.tfstate`)
- [ ] State bucket has versioning and encryption (confirmed in `bootstrap/main.tf`)

## Output format

```
## /security — YYYY-MM-DD

### Findings
[BLOCK] iam.tf:14 — Lambda role grants s3:* on Resource: "*"
[WARN]  lambda/chatbot/index.py:23 — full event dict logged at INFO level
[INFO]  main.tf:45 — consider enabling S3 access logging for audit trail

### Summary
2 findings: 1 BLOCK must be fixed before commit, 1 WARN to address.

### Next step
Fix iam.tf:14 — replace s3:* with s3:GetObject, s3:PutObject scoped to the specific bucket ARN.
```

If no findings: write `No findings — all checks pass.` under Findings.
```

- [ ] **Step 2: Verify the file exists**

Run: `Get-Content .claude\skills\security\SKILL.md | Select-Object -First 3`
Expected first line: `# Security Review`

---

### Task 2: Write `/refactoring` skill

**Files:**
- Create: `.claude/skills/refactoring/SKILL.md`

- [ ] **Step 1: Create the file with the full content below**

Write `.claude/skills/refactoring/SKILL.md`:

```markdown
# Refactoring Review

Run after writing or expanding a function to catch complexity, hidden failures,
and duplication before they compound.

## How to use

Type `/refactoring` after modifying or creating any function, especially in `lambda/*/index.py`.

## Steps

1. Read the changed function(s) from the current diff.
2. Run the checklist below against each changed function.
3. Report findings using the output format.

## Checklist

### Size and complexity
- [ ] Lambda handler ≤ 40 lines — if longer, flag sections that should be extracted to helpers
- [ ] Nesting depth ≤ 4 levels — if deeper, identify guard-clause opportunities (early returns for error cases)
- [ ] No function doing more than one thing — the function name describes exactly what it does

### Error handling
- [ ] No bare `except:` or `except Exception as e: pass` — errors must surface or be logged and re-raised
- [ ] No silent swallowing of boto3 `ClientError` — at minimum log the error code and re-raise

### Duplication
- [ ] Same logic (DynamoDB write, SSM fetch, chunk splitting) does not appear in 3+ Lambda packages
- [ ] If a shared module is warranted: it has no AWS-service-specific dependency (pure logic only)

### Conditional logic safety
- [ ] When flattening nested `if` blocks with guard clauses, verify happy path and all branch outcomes
  are identical before and after
- [ ] Business rule ordering (e.g., check escalation before abuse) preserved after any restructuring

## Output format

```
## /refactoring — YYYY-MM-DD

### Findings
[ACTION]   lambda/chatbot/index.py:12-67 — handler is 55 lines; extract Gemini call to call_ai_provider()
[DEFER]    lambda/ingest/index.py:34 — chunk-split logic duplicated in query/index.py but only 2 packages;
           flag again if a third package adds it
[RESOLVED] lambda/query/index.py:18 — broad except replaced with specific ClientError handling

### Summary
1 ACTION to address now, 1 DEFER recorded, 1 already resolved.

### Next step
Extract lines 23-45 of lambda/chatbot/index.py into a call_ai_provider(prompt, history) helper function.
```

If no findings: write `No findings — all checks pass.` under Findings.
```

- [ ] **Step 2: Verify the file exists**

Run: `Get-Content .claude\skills\refactoring\SKILL.md | Select-Object -First 3`
Expected first line: `# Refactoring Review`

---

### Task 3: Write `/cicd` skill

**Files:**
- Create: `.claude/skills/cicd/SKILL.md`

- [ ] **Step 1: Create the file with the full content below**

Write `.claude/skills/cicd/SKILL.md`:

```markdown
# CI/CD Check

Run after adding a new resource, Lambda function, or project to verify Terraform wiring
is complete and GitHub Actions workflows cover the new component.

## How to use

Type `/cicd` after adding any new Lambda function, Terraform resource, or project directory.

## Steps

1. Identify the new resource or function from the current diff.
2. Run Part 1 (Terraform wiring) against the relevant project's Terraform files.
3. Run Part 2 (GitHub Actions) against `.github/workflows/`.
4. Report findings using the output format.

## Part 1 — Terraform wiring

For each new Lambda function:
- [ ] `aws_lambda_function` resource present in `main.tf`
- [ ] `aws_cloudwatch_log_group` for the function in `main.tf` (`retention_in_days` set)
- [ ] `aws_lambda_permission` for the trigger (S3, API Gateway, or EventBridge) in `main.tf`
- [ ] IAM role and policy in `iam.tf` — least-privilege actions only
- [ ] New input values declared as variables in `variables.tf` (not hardcoded in `main.tf`)
- [ ] Endpoint URL or function ARN exported in `outputs.tf`

For each new project directory:
- [ ] `backend.tf` present pointing to bootstrap S3 bucket with unique key (`p[N]/terraform.tfstate`)
- [ ] `terraform.tfvars` present (gitignored) with `suffix` and `alert_email` filled in
- [ ] `variables.tf` declares `aws_region`, `project_name`, `suffix`, `common_tags` at minimum

## Part 2 — GitHub Actions

- [ ] `.github/workflows/terraform-init.yml` (or equivalent) includes the new project directory
- [ ] Workflow does not hardcode AWS credentials — uses `${{ secrets.AWS_ACCESS_KEY_ID }}` pattern
- [ ] Workflow references the correct relative path to the project directory
- [ ] No new workflow file introduces a `pull_request` trigger without environment protection

## Output format

```
## /cicd — YYYY-MM-DD

### Findings
[MISSING] project5-document-engine/outputs.tf — query API endpoint URL not exported
[WARN]    .github/workflows/terraform-init.yml:12 — project5 directory not in matrix
[OK]      project5-document-engine/backend.tf — remote state backend present and correctly keyed

### Summary
1 MISSING and 1 WARN to address before deploy.

### Next step
Add query_api_endpoint output to project5-document-engine/outputs.tf, then add
project5-document-engine to the workflow matrix at .github/workflows/terraform-init.yml:12.
```

If no findings: write `No findings — all checks pass.` under Findings.
```

- [ ] **Step 2: Verify the file exists**

Run: `Get-Content .claude\skills\cicd\SKILL.md | Select-Object -First 3`
Expected first line: `# CI/CD Check`

---

### Task 4: Write `/design` skill

**Files:**
- Create: `.claude/skills/design/SKILL.md`

- [ ] **Step 1: Create the file with the full content below**

Write `.claude/skills/design/SKILL.md`:

```markdown
# Design Review

Run after adding a new feature, function, or project to verify design docs are in sync
and the architecture follows P1–P5 patterns.

## How to use

Type `/design` after adding a new feature, Lambda function, project directory, or any
change that affects the system architecture.

## Steps

1. Identify the active project (P1–P5) from the changed files.
2. Run Part 1 (doc sync) against `docs/design/p[N]-*/design.md` and `docs/todo.md`.
3. Run Part 2 (architecture quality) against the changed functions.
4. Report findings using the output format.

## Part 1 — Doc sync

- [ ] `docs/design/p[N]-*/design.md` exists for the active project
- [ ] New resource or function appears in the architecture section of the design doc
- [ ] ASCII architecture diagram in design doc reflects current `main.tf` resource graph
- [ ] AWS resource table lists the new service with its role and free-tier note
- [ ] `docs/todo.md` validation checklist includes a test item for the new function
- [ ] Any reconsidered decision is marked superseded — not silently removed

## Part 2 — Architecture quality

- [ ] New function has one clear purpose — its name states what it does without "and" or "or"
- [ ] Naming follows conventions:
  - Terraform resources: `kebab-case` with `p[N]-` prefix (e.g., `p5-doc-engine-ingest`)
  - Python functions: `snake_case` (e.g., `fetch_conversation_history`)
  - Environment variables: `UPPER_SNAKE_CASE`
- [ ] Lambda handler is thin (≤ 20 lines of orchestration) — heavy logic in helper functions
- [ ] New function reuses an existing P1–P5 pattern where one fits:
  - Storage: P1 S3+CloudFront or P2 DynamoDB PAY_PER_REQUEST+TTL
  - Notifications: P3 SNS topic+subscription
  - Secrets: P4 SSM Parameter Store
  - If no pattern fits, the new pattern is documented in the design doc

## Output format

```
## /design — YYYY-MM-DD

### Findings
[STALE]   docs/design/p5-document-engine/design.md — missing; needs to be created
[UPDATE]  docs/todo.md — P5 validation checklist not present
[CONCERN] lambda/ingest/index.py:lambda_handler — handler is 80 lines; orchestration not
          separated from processing logic
[OK]      Naming — all Terraform resources follow p5- prefix and kebab-case

### Summary
2 doc gaps and 1 architecture concern to address.

### Next step
Create docs/design/p5-document-engine/design.md following the pattern in
docs/design/p4-ai-chatbot/design.md.
```

If no findings: write `No findings — all checks pass.` under Findings.
```

- [ ] **Step 2: Verify the file exists**

Run: `Get-Content .claude\skills\design\SKILL.md | Select-Object -First 3`
Expected first line: `# Design Review`

---

### Task 5: Write `/changelog` skill

**Files:**
- Create: `.claude/skills/changelog/SKILL.md`

- [ ] **Step 1: Create the file with the full content below**

Write `.claude/skills/changelog/SKILL.md`:

```markdown
# Changelog Writer

Reads the current session's work and writes a populated changelog entry following the
project's required format. Always run this last, after all other skills.

## How to use

```
/changelog              — infers type from diff (upgrade / bug / test)
/changelog upgrade      — forces [upgrade] type
/changelog bug          — forces [bug] type
/changelog test         — forces [test] type
```

## Steps

1. Run `git diff HEAD` to see all changes in this session.
2. Determine the change type:
   - `upgrade` — new feature, improvement, or documentation change
   - `bug` — fix for incorrect behavior in any environment
   - `test` — new or updated tests only
   - If a type argument was passed, use that instead of inferring.
3. Draft a subject: title case, no special characters, ≤ 60 chars.
4. Fill every required field in the template — no field may be blank or written as "TBD".
5. Write the file to `docs/changelog/YY-MM-DD [type] Subject.md`.
6. Add one index row to `docs/changelog/README.md`.

## Required fields

| Field | Rule |
|-------|------|
| `Type` | Exactly one of: `test`, `upgrade`, `bug` |
| `Files Changed` | Table: file path · function/class name · one-line description of what changed |
| `Why Changed` | The trigger or problem — specific enough a future session needs no git blame. Must not be empty. |
| `Contents Diff` | Before/after code snippet for every changed function with prior logic. Omit only for brand-new files. |
| `Improvements` | Concrete — "reduced Lambda cold start by removing unused import" not "improved performance" |
| `Performance Impact` | Measurable change (latency ms, memory MB, line count delta). Write "none" only if genuinely not applicable — never as a shortcut. |
| `Agents Consulted` | Comma-separated list of skills run: `/security`, `/refactoring`, `/cicd`, `/design`, or "none" |
| `Findings Addressed` | Each BLOCK/WARN finding fixed, with file:line reference |
| `Findings Deferred` | Any WARN/INFO not fixed, with justification. Write "none" if all were addressed. |

## Validation before writing

Stop and ask the user if any of these are missing:
- `Why Changed` is empty
- `Performance Impact` is empty (not "none" — literally empty)
- `Contents Diff` is omitted for a file that had prior logic

## Index row to add in `docs/changelog/README.md`

```
| YY-MM-DD | type | [Subject](YY-MM-DD%20[type]%20Subject.md) | file1.tf, file2.py |
```

## After writing

Confirm to the user:
- The changelog file path that was written
- The index row that was added to README.md
- Any field where an assumption was made (state what was assumed)
```

- [ ] **Step 2: Verify the file exists**

Run: `Get-Content .claude\skills\changelog\SKILL.md | Select-Object -First 3`
Expected first line: `# Changelog Writer`

---

### Task 6: Update CLAUDE.md Section 5 decision matrix

**Files:**
- Modify: `.claude/CLAUDE.md` (Section 5 — Agent Orchestration, decision matrix table)

- [ ] **Step 1: Read the current decision matrix**

Read `.claude/CLAUDE.md` lines 68–90. The table currently has these rows:

```
| Terraform resource add/change | `security` |
| IAM role or policy change | `security` |
| New Lambda env var or external input | `security` |
| Planned rewrite or 3+ duplicate patterns | `refactoring` |
| Function > 40 lines or 4+ nesting levels | `refactoring` |
| New feature, plan, or design decision | `idea-management` |
| `docs/todo.md` or design doc out of sync | `idea-management` |
| Pre-deploy review | `security`, `refactoring` |
```

- [ ] **Step 2: Replace the decision matrix table with the updated version**

Find this exact block in `.claude/CLAUDE.md`:

```
| Change Type | Agents to Consult |
|-------------|-------------------|
| Terraform resource add/change | `security` |
| IAM role or policy change | `security` |
| New Lambda env var or external input | `security` |
| Planned rewrite or 3+ duplicate patterns | `refactoring` |
| Function > 40 lines or 4+ nesting levels | `refactoring` |
| New feature, plan, or design decision | `idea-management` |
| `docs/todo.md` or design doc out of sync | `idea-management` |
| Pre-deploy review | `security`, `refactoring` |
```

Replace with:

```
| Change Type | Agents to Consult | Skills to Run |
|-------------|-------------------|---------------|
| Terraform resource add/change | `security` | `/security` `/cicd` |
| IAM role or policy change | `security` | `/security` |
| New Lambda env var or external input | `security` | `/security` |
| Planned rewrite or 3+ duplicate patterns | `refactoring` | `/refactoring` |
| Function > 40 lines or 4+ nesting levels | `refactoring` | `/refactoring` |
| New feature, plan, or design decision | `idea-management` | `/design` |
| `docs/todo.md` or design doc out of sync | `idea-management` | `/design` |
| Pre-deploy review | `security`, `refactoring` | `/security` `/refactoring` `/cicd` `/design` |
| New Lambda function (full) | `security`, `refactoring` | `/security` `/refactoring` `/cicd` `/design` |
| Any completed change | — | `/changelog` |
```

- [ ] **Step 3: Verify the file updated correctly**

Run: `Select-String -Path .claude\CLAUDE.md -Pattern "Skills to Run"`
Expected: one match on the updated header row.

---

### Task 7: Commit all skills

- [ ] **Step 1: Stage the new skill files and CLAUDE.md update**

```powershell
git add .claude/skills/security/SKILL.md
git add .claude/skills/refactoring/SKILL.md
git add .claude/skills/cicd/SKILL.md
git add .claude/skills/design/SKILL.md
git add .claude/skills/changelog/SKILL.md
git add .claude/CLAUDE.md
```

- [ ] **Step 2: Verify staged files**

Run: `git status`
Expected: 6 files staged — 5 new SKILL.md files + modified CLAUDE.md. No unintended files.

- [ ] **Step 3: Commit**

```powershell
git commit -m "feat: add 5 project-local quality-gate skills

Add /security, /refactoring, /cicd, /design, /changelog as standalone
SKILL.md files under .claude/skills/. Update CLAUDE.md Section 5
decision matrix to cross-reference skills alongside agent files.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

- [ ] **Step 4: Verify commit**

Run: `git log --oneline -1`
Expected: commit message starts with `feat: add 5 project-local quality-gate skills`

---

## Self-Review

**Spec coverage:**
- `/security` — Task 1 ✓
- `/refactoring` — Task 2 ✓
- `/cicd` (Terraform + GitHub Actions) — Task 3 ✓
- `/design` (doc sync + architecture quality) — Task 4 ✓
- `/changelog` (with type variants) — Task 5 ✓
- Output format (`[SEVERITY] file:line — description`) — embedded in each SKILL.md ✓
- CLAUDE.md update — Task 6 ✓
- Commit — Task 7 ✓

**Placeholder scan:** No TBD, TODO, or vague steps. All SKILL.md content is fully written out in the plan steps.

**Consistency:** Output tag names are consistent between spec and SKILL.md content throughout all tasks.
