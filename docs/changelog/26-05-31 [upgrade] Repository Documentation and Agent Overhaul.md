# 26-05-31 [upgrade] Repository Documentation and Agent Overhaul

**Type:** upgrade
**Branch / Commit:** dev / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `.agents/README.md` | Orchestration index | Rewritten: 3-agent table + slimmed decision matrix |
| `.agents/refactoring.md` | Entire file | Rewritten concise (163→35 lines); removed P3-specific debt register |
| `.agents/security.md` | Entire file | Rewritten concise (98→40 lines); added P4 `GEMINI_API_KEY` note |
| `.agents/idea-management.md` | New file | New agent: captures concepts, plans, design decisions |
| `.agents/file-structure.md` | Deleted | Removed — not in active 3-agent set |
| `.agents/code-reviewer.md` | Deleted | Removed |
| `.agents/architecture.md` | Deleted | Removed |
| `.agents/dataclass.md` | Deleted | Removed |
| `.agents/event-sourcing.md` | Deleted | Removed |
| `.agents/strategy-pattern.md` | Deleted | Removed |
| `.agents/solid-principles.md` | Deleted | Removed |
| `.agents/python-features.md` | Deleted | Removed |
| `.agents/python-idioms.md` | Deleted | Removed |
| `README.md` (root) | Entire file | Rewritten as P1–P4 portfolio overview with links to design docs; P3 content moved to design folder |
| `.claude/CLAUDE.md` | §5 Agent Orchestration | Decision matrix updated to reference 3 agents; P4 noted as active project |
| `docs/design/p1-static-web/design.md` | New file | P1 architecture, resource inventory, IAM notes, cost, "How P4 reuses this" |
| `docs/design/p2-serverless-pipeline/design.md` | New file | P2 architecture, resource inventory, IAM notes, cost, "How P4 reuses this" |
| `docs/design/p3-smart-vault/design.md` | New file | P3 architecture + full original root README content preserved |
| `docs/todo.md` | Entire file | Written: complete P4 build plan (8 sections) |
| `docs/event-sourcing.md` | Deleted | Orphaned reference doc |
| `docs/python-advanced-features.md` | Deleted | Orphaned |
| `docs/python-dataclass-advanced.md` | Deleted | Orphaned |
| `docs/python-idioms.md` | Deleted | Orphaned |
| `docs/solid-principles.md` | Deleted | Orphaned |
| `docs/strategy-pattern-parameters.md` | Deleted | Orphaned |

## Why Changed

Root `README.md` documented only P3. `.agents/` carried 12 heavyweight specs tied to a P3-specific workflow. `docs/` had no per-project design references, making it hard to trace which P1–P3 patterns P4 reuses. P4 is now the flagship project and the supporting docs needed to reflect that.

Decision: slim agents to 3 focused specs (refactoring, idea-management, security) matching the P4-centric workflow; delete the 9 orphaned specs and their 6 paired reference docs; create per-project design folders so P1–P3 architecture is discoverable.

## Contents Diff

**`.claude/CLAUDE.md` — §5 decision matrix (before → after)**

```
# Before
| New file or directory            | file-structure         |
| Any Python edit                  | code-reviewer          |
| New data structure               | dataclass              |
| Terraform resource add/change    | architecture, security |
| IAM role or policy change        | security               |
| Planned rewrite or 3+ patterns   | refactoring            |
| Pre-deploy review                | security, architecture |

# After
| Terraform resource add/change         | security               |
| IAM role or policy change             | security               |
| New Lambda env var or external input  | security               |
| Planned rewrite or 3+ patterns        | refactoring            |
| Function > 40 lines or 4+ nesting     | refactoring            |
| New feature, plan, or decision        | idea-management        |
| docs/todo.md or design doc out of sync| idea-management        |
| Pre-deploy review                     | security, refactoring  |
```

## Improvements

- Single root README now navigates the full 4-project portfolio
- Per-project design docs (`docs/design/`) make P1–P3 architecture referenceable from P4 context
- Agent set trimmed to 3 focused agents; decision matrix matches current project scope
- `docs/todo.md` is the canonical P4 build plan

## Performance Impact

none

## Agents Consulted

idea-management

## Findings Addressed

none

## Findings Deferred

none
