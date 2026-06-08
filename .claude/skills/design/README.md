# /design

**When to run:** After adding a new feature, Lambda function, project directory, or any change that affects architecture.

## What it checks

### Part 1 — Doc sync

| Check | Location |
|-------|----------|
| Design doc exists for the active project | `docs/design/p[N]-*/design.md` |
| New resource/function in architecture section | same file |
| ASCII diagram matches current `main.tf` | same file |
| AWS resource table updated | same file |
| Validation checklist updated | `docs/todo.md` |
| Superseded decisions marked (not silently removed) | same file |

### Part 2 — Architecture quality

| Check | Rule |
|-------|------|
| Single purpose | Function name has no "and" or "or" |
| Naming | Terraform: `kebab-case` with `p[N]-` prefix · Python: `snake_case` · Env vars: `UPPER_SNAKE_CASE` |
| Thin handler | ≤ 20 lines of orchestration — heavy logic in helpers |
| Pattern reuse | Uses P1 S3/CDN, P2 DynamoDB+TTL, P3 SNS, or P4 SSM where applicable |

## Output tags

| Tag | Meaning | Action required |
|-----|---------|-----------------|
| `[STALE]` | Doc missing or not reflecting current code | Create or update before next session |
| `[UPDATE]` | Doc exists but a section needs updating | Update the specific section |
| `[CONCERN]` | Architecture quality issue | Refactor or document the exception |
| `[OK]` | Confirmed correct | No action |

## Example

```
/design
```

```
## /design — 26-06-08

### Findings
[STALE]   docs/design/p5-document-engine/design.md — missing
[UPDATE]  docs/todo.md — P5 validation checklist not present
[OK]      Naming — all Terraform resources follow p5- prefix and kebab-case

### Summary
2 doc gaps to address.

### Next step
Create docs/design/p5-document-engine/design.md following docs/design/p4-ai-chatbot/design.md.
```

## Tips

- A `[STALE]` on a design doc means the next session will start with wrong context — fix it before ending the session.
- The pattern reuse check is the most valuable one: if you're about to invent a DynamoDB schema that doesn't follow the P2 TTL pattern, `/design` will catch it.
- Run `/design` even for small changes — a one-line Lambda addition that isn't in the architecture diagram causes doc drift that compounds over sessions.
