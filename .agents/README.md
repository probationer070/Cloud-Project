# Agent Orchestration System

This directory defines specialized sub-agents for the Smart Vault project.
Each agent file is a self-contained specification that any AI coding agent
(Claude Code, OpenAI Codex, GitHub Copilot Workspace, etc.) can parse and execute.

## Sub-Agents

| Agent | File | Scope |
|-------|------|-------|
| File Structure | `file-structure.md` | Project layout, naming, directory organization |
| Code Reviewer | `code-reviewer.md` | Code quality, style, correctness |
| Architecture | `architecture.md` | Infrastructure design, component relationships |
| Refactoring | `refactoring.md` | Technical debt, pattern consolidation |
| Data Models | `dataclass.md` | Python dataclass / TypedDict / type annotation patterns |
| Security | `security.md` | IAM, encryption, secrets, input validation |
| Event Sourcing | `event-sourcing.md` | Immutable events, projections, snapshotting, versioning, CQRS |
| Strategy Pattern | `strategy-pattern.md` | Parameter handling, constructor injection, anti-patterns, composition root |
| SOLID Principles | `solid-principles.md` | SRP, OCP, LSP, ISP, DIP — coupling, abstraction, testability |
| Python Features | `python-features.md` | cache, Protocol, replace, pairwise, pathlib, contextvars, match, ExitStack |
| Python Idioms | `python-idioms.md` | Functions vs classes, context managers, EAFP, logging, generators, type hints |

## Orchestration Protocol

The main agent (Claude) orchestrates sub-agents according to this decision matrix:

| Change Type | Required Agents |
|-------------|----------------|
| New file or directory | file-structure |
| Any Python edit | code-reviewer, dataclass (if data structures involved) |
| Terraform edit | architecture, security |
| IAM / policy edit | security |
| New data structure | dataclass, code-reviewer |
| New event class or append-only store | event-sourcing, dataclass |
| Projection or replay logic added | event-sourcing |
| CQRS or event-driven integration | event-sourcing, architecture |
| Strategy / Policy / Handler class added | strategy-pattern, dataclass |
| `**kwargs` found on domain interface | strategy-pattern, code-reviewer |
| Shared parameter object spans strategies | strategy-pattern, dataclass |
| God class or mixed-responsibility module | solid-principles, code-reviewer |
| New Protocol or ABC added | solid-principles, code-reviewer |
| Concrete dependency created inside constructor | solid-principles |
| Pre-deploy domain logic review | solid-principles, security, architecture |
| Any Python edit (feature opportunities) | python-features, code-reviewer |
| Async Lambda handler added or modified | python-features (contextvars check), security |
| Manual memoization or os.path usage found | python-features |
| Stateless utility class or print() in Lambda | python-idioms |
| New Python file added to lambda/ | python-idioms, python-features, code-reviewer |
| Pre-refactor | refactoring, code-reviewer |
| Pre-deploy review | security, architecture |

## Workflow

```
1. Identify change type → select relevant sub-agents from matrix above
2. Run each agent's checklist against the affected files
3. Address all BLOCK findings before committing
4. Address WARN findings or explicitly justify deferral
5. Record outcome in docs/CHANGELOG.md using the standard template
```

## Output Severity Levels

- **BLOCK** — Must fix before commit. Correctness bug, security vulnerability, or broken contract.
- **WARN** — Should fix. Technical debt, style deviation, or fragile pattern.
- **INFO** — Observation only. No action required; context for future work.

## Interoperability Notes

These files use plain CommonMark markdown with no proprietary syntax.
Any agent that can read a file can consume these specifications.
The `## Trigger`, `## Checklist`, and `## Output` sections are the minimum
contract each agent file must provide.
