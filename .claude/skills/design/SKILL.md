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
