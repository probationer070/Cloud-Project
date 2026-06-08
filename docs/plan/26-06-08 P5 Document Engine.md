# Plan: P5 Document Engine — Start and Validate

**Opened:** 26-06-08
**Closed:** —
**Active Project:** P5 — Intelligent Document Analysis Engine (RAG)

---

## Context

P5 code was committed on 26-06-08 as "p5 need to check is it works." The Terraform and two Lambda
functions exist but have never been applied or tested. Several process gaps remain before P5 can
be considered a proper project alongside P1–P4:

- README is Korean-only (all prior projects were translated to English in 26-06-06).
- Double-nested folder: `project5-document-engine/project5-document-engine/` — the inner folder
  should live directly at `project5-document-engine/`.
- No design doc at `docs/design/p5-document-engine/design.md`.
- No remote-state backend (`backend.tf`) — P4 added one; P5 should follow the same pattern.
- No changelog entry for P5 creation.
- `docs/todo.md` still describes the P4 build plan; it needs a P5 equivalent or an update.

Cost warning: OpenSearch `t3.small.search` costs ~$0.036/hr → ~$26/month.
**Run `terraform destroy` immediately after each test session.**

---

## Goals

1. **Fix folder nesting** — move `project5-document-engine/project5-document-engine/*` up one level
   so the layout matches P1–P4.
   Verify: `project5-document-engine/main.tf` exists (not `project5-document-engine/project5-document-engine/main.tf`).

2. **Translate README to English** — follow the style of `project4-ai-chatbot/README.md`.
   Verify: no Korean characters remain in `project5-document-engine/README.md`.

3. **Add design doc** — create `docs/design/p5-document-engine/design.md` following the
   pattern of `docs/design/p4-ai-chatbot/design.md`.
   Verify: file exists and covers architecture, AWS resources, cost note, and reuse of P1–P4 patterns.

4. **Add remote-state backend** — create `project5-document-engine/backend.tf` pointing at the
   same S3 bucket used by P4 (`bootstrap/`), with a distinct `key` (e.g., `p5/terraform.tfstate`).
   Verify: `terraform init` succeeds without local state.

5. **Deploy and validate** — run `terraform apply`, execute the six-step test sequence from the
   README (index creation → PDF upload → DynamoDB status → OpenSearch count → query → destroy).
   Verify: all seven checklist items in `project5-document-engine/README.md` are checked off.
   **Run `terraform destroy` when done.**

6. **Write changelog entry** — one entry per significant action above (folder fix, README
   translation, design doc, backend, deploy/test).

---

## Known Blockers

- [ ] AWS Bedrock model access in `us-east-1`: `amazon.titan-embed-text-v2:0` and
      `anthropic.claude-3-haiku-20240307-v1:0` must be enabled before `terraform apply`.
- [ ] `variables.tf` needs `suffix` and `alert_email` filled in before apply.
- [ ] Bootstrap S3 state bucket must exist (created by `bootstrap/` in P4 setup) before adding
      `backend.tf` for P5.
- [ ] Cost budget: confirm willingness to spend ~$0.86/day while OpenSearch is running.

---

## Files to Read First

- `project5-document-engine/project5-document-engine/README.md` — architecture and deploy steps
- `project5-document-engine/project5-document-engine/main.tf` — full infrastructure
- `project5-document-engine/project5-document-engine/lambda/ingest/index.py` — ingest pipeline
- `project5-document-engine/project5-document-engine/lambda/query/index.py` — query + RAG response
- `project4-ai-chatbot/backend.tf` — reference for writing P5's backend.tf
- `docs/design/p4-ai-chatbot/design.md` — reference style for the new P5 design doc
- `docs/changelog/template.md` — required before writing any changelog entries

---

## Out of Scope

- API key auth on the query endpoint (P4 used API Gateway keys; P5 currently has none — add later).
- Multi-file upload UI (S3 console / CLI upload is sufficient for now).
- P6 planning.
