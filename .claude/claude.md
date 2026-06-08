# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

## 5. Agent Orchestration

**Consult the right sub-agent before and after every change.**

Specialized sub-agent specifications live in `.agents/`. Each file defines a focused checklist
and output format. Read the relevant agent file(s) before starting a task, then run its checklist
against your changes before committing.

The active project is **P4 (AI Chatbot)**; P1–P3 are reused building blocks whose
architecture is documented under `docs/design/`.

**Decision matrix — which agents to consult:**

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

**Severity protocol:**
- `[BLOCK]` finding → fix before proceeding, no exceptions
- `[WARN]` finding → fix now, or record deferral justification in the change log file
- `[INFO]` finding → no action required; note in CHANGELOG if relevant

The orchestration overview and agent index are in `.agents/README.md`.

## 6. Change Logging

**Every significant change gets its own log file in `docs/changelog/`.**

Write a log file for every change that:
- Modifies, adds, or deletes a source file
- Changes Terraform infrastructure
- Refactors or reorganizes code
- Addresses a finding from a sub-agent

**File naming — required format:**
```
YY-MM-DD [type] Subject.md
```
- `type` must be exactly one of: `test`, `upgrade`, `bug`
- Subject: short title in title case, spaces allowed, no special characters
- Example: `26-05-30 [upgrade] Strategy Pattern Agent.md`

**Required fields (copy from `docs/changelog/template.md`):**
- `Type` — test / upgrade / bug
- `Files Changed` — list each file with the specific functions or classes modified
- `Why Changed` — the trigger or problem; be specific enough that a future session needs no git blame
- `Contents Diff` — before/after snippet for every non-trivial logic change (omit for new files)
- `Improvements` — what specifically was made better
- `Performance Impact` — measurable change (latency, memory, line count, test time); write "none" if truly not applicable
- `Agents Consulted` — comma-separated list
- `Findings Addressed` — BLOCK/WARN findings that were fixed, or "none"
- `Findings Deferred` — anything not fixed, with justification

After writing the file, add one index row to `docs/changelog/README.md`.

Entries with empty `Why Changed` or `Performance Impact` (not "none") are invalid.

**This logging requirement is working if:** future AI sessions can understand exactly which
function changed, why, and what it looked like before — without reading git history.

## 7. Error Recording

**Every confirmed bug gets a record in `docs/error/`.**

Write a record when:
- A bug caused incorrect behavior in any environment (local, dev, or prod)
- A silent failure was discovered (wrong output, wrong data, no error raised)
- A test caught a regression introduced by a code change
- An agent `[BLOCK]` or `[WARN]` finding revealed an existing defect in running code

**Do NOT write a record for:**
- Syntax/type errors caught before any execution
- Failing tests that were never passing during development
- Configuration mistakes requiring no code change

**Process:**
1. Reproduce and fix the bug first
2. Copy `docs/error/template.md` → `docs/error/ERR-NNN-short-description.md`
3. Fill all fields: symptom, root cause, fix applied, prevention checklist, test added
4. Add an index row to `docs/error/README.md`
5. Update any agent checklist that would have caught this — record which in the Prevention section
6. Add a CHANGELOG entry referencing the ERR-NNN ID

**This is working if:** the same class of bug never appears twice without a prior ERR record
that should have prevented it.

## 8. Session Planning

**Write a plan before ending any session with unfinished work.**

Write a plan file in `docs/plan/` whenever:
- You finish a session but the active project still has open goals.
- A significant decision was made that the next session needs to understand before touching code.
- A new project phase is starting and the entry point is non-obvious.

**File naming:**
```
YY-MM-DD Short Title.md
```
Example: `26-06-08 P5 Document Engine.md`

**Required sections (copy from `docs/plan/template.md`):**
- `Context` — what was happening and why this is next
- `Goals` — ordered, with a concrete verify condition for each
- `Known Blockers` — prerequisites (credentials, cost budget, AWS access) that must be true before starting
- `Files to Read First` — files the next session must read before touching anything
- `Out of Scope` — work explicitly deferred

After writing the file, add one index row to `docs/plan/README.md`.
Close a plan by adding a `Closed:` date and the changelog reference to the plan file and index row.

**At session start:** check `docs/plan/README.md` for open plans. If one covers your active
project, read it before reading any code.

**This is working if:** a new session can orient itself and start the right task without asking
"where did we leave off?"