# 26-05-31 [upgrade] Root README Expanded with Service Detail

**Type:** upgrade
**Branch / Commit:** dev / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `README.md` | Entire file | Expanded from navigation table to per-project sections with architecture diagrams, AWS service tables (role + trigger conditions), and links |

## Why Changed

Root README showed only a one-line stack summary per project. A reader had to open design docs to understand what each service does and when it activates. The expanded README makes each project self-describing at a glance — architecture flow, every service with its role and trigger condition — without replacing the detailed design docs.

## Contents Diff

```
# Before
| P1 | Static Web | S3 + CloudFront + WAF | [design] |
| P2 | Serverless Pipeline | S3 + SQS + Lambda×3 + DynamoDB | [design] |
...

# After
Per-project sections each containing:
- One-line purpose statement
- ASCII architecture/flow diagram
- Service table: service | role | when it activates
- Links to design doc, file-structure.md, ADRs
```

## Improvements

- Each project is self-describing in README without opening any other file
- Trigger conditions ("when it works") documented for every service
- ADR and file-structure links added to P4 section
- `docs/adr/` added to repository structure map

## Performance Impact

none

## Agents Consulted

idea-management

## Findings Addressed

none

## Findings Deferred

none
