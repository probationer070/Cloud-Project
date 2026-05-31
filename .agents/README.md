# Agent Orchestration System

This directory defines the focused sub-agents for the Cloud Project (P1–P4).
Each agent file is a self-contained specification that any AI coding agent
(Claude Code, OpenAI Codex, GitHub Copilot Workspace, etc.) can parse and execute.

## Sub-Agents

| Agent | File | Scope |
|-------|------|-------|
| Refactoring | `refactoring.md` | Technical debt, pattern consolidation, safe rewrites |
| Idea Management | `idea-management.md` | Capturing concepts, plans, and design decisions |
| Security | `security.md` | IAM least-privilege, secrets, input validation, encryption |

## Orchestration Protocol

The main agent (Claude) orchestrates sub-agents according to this decision matrix:

| Change Type | Required Agents |
|-------------|----------------|
| Terraform resource add/change | security |
| IAM role or policy change | security |
| New Lambda env var or external input | security |
| Planned rewrite or 3+ duplicate patterns | refactoring |
| Function > 40 lines or 4+ nesting levels | refactoring |
| New feature, plan, or design decision | idea-management |
| `docs/todo.md` or design doc out of sync | idea-management |
| Pre-deploy review | security, refactoring |

## Workflow

```
1. Identify change type → select relevant sub-agents from matrix above
2. Run each agent's checklist against the affected files
3. Address all BLOCK findings before committing
4. Address WARN findings or explicitly justify deferral
5. Record the outcome in docs/changelog/ using the standard template
```

## Output Severity Levels

- **BLOCK** — Must fix before commit. Correctness bug, security vulnerability, or broken contract.
- **WARN** — Should fix. Technical debt, style deviation, or fragile pattern.
- **INFO** — Observation only. No action required; context for future work.

(The refactoring and idea-management agents use action-oriented tags —
`[ACTION]/[DEFER]/[RESOLVED]` and `[RECORD]/[UPDATE]/[STALE]` respectively.)

## Interoperability Notes

These files use plain CommonMark markdown with no proprietary syntax.
Any agent that can read a file can consume these specifications.
The `## Role`, `## Trigger`, `## Checklist`, and `## Output` sections are the
minimum contract each agent file must provide.
