# Plan: P5 Document Engine — Start and Validate

**Opened:** 26-06-08
**Closed:** 26-06-10 — `docs/changelog/26-06-10 [upgrade] P5 Textract Replaced with pypdf uv Packaging and Container Prep.md`
**Active Project:** P5 — Intelligent Document Analysis Engine (RAG)
**Last Updated:** 26-06-10

---

## Context

P5 code was committed on 26-06-08. As of 26-06-10:

**Completed this session (26-06-10):**
- README translated from Korean to English — changelog `26-06-10 [upgrade] P5 README English Rewrite and Textract Region Fix.md`
- Textract client now uses explicit `region_name=AWS_REGION` (consistent with Bedrock client)
- Common Errors section updated with correct Textract troubleshooting (account activation wall)
- Expected CloudWatch log output corrected (was showing async job ID; code uses sync API)
- AWS account activation confirmed — Bedrock is accessible, account is active

**Still outstanding:**
- No design doc at `docs/design/p5-document-engine/design.md`
- No remote-state backend (`backend.tf`) — P4 has one; P5 should follow the same pattern
- `docs/todo.md` not updated for P5

### Update — 26-06-10 (session 2: live validation)

First real end-to-end test run. The pipeline was exercised through the query API and three
sequential failures were found and fixed, each one previously masked by the one before it:

1. **OpenSearch kNN 400** — the live index was created (via this plan's old Step 3) with
   `dimension: 1536`, but the Lambda now embeds at 1024 (ERR-004). Resolved by deleting and
   recreating the index at 1024; Step 3 in this plan corrected to match.
2. **Claude 3 Haiku retired** — `ResourceNotFoundException ... marked by provider as Legacy`.
   Upgraded `bedrock_model_id` to `anthropic.claude-3-5-haiku-20241022-v1:0` (ERR-005).
3. **IAM glob mismatch** — `AccessDeniedException`; the policy glob `anthropic.claude-3-haiku*`
   did not match `claude-3-5-haiku`. Widened to `anthropic.claude*` (ERR-005).

**Decision (via `/office-hours`):** keep generation on Bedrock Claude rather than pivoting to
Gemini, for portfolio differentiation from P4 — recorded in ADR 0003.

**Goal 3 (validate) is still OPEN** — but the supposed final blocker was wrong. AWS has
**retired the Bedrock "Model access" page**; serverless models auto-enable on first
`InvokeModel` and access is governed purely by IAM (already fixed). There is no separate console
grant to wait on. The only residual nuance: a first-time account may need to submit a one-time
Anthropic use-case form (Bedrock console → Model catalog → the model). Once `terraform apply`
has pushed the new model env var, re-run Step 6/7 and confirm the query API returns `answer` +
`sources`.

### Update — 26-06-11 (session 3: Goal 3 VALIDATED ✅)

End-to-end query validation now passes. Three more stacked failures were found and fixed past
the ERR-005 ones (full analysis in ERR-006):

1. **kNN 400** — the live `documents` index had `embedding` mapped as `float`, not `knn_vector`
   (auto-created by an ingest write before Step 4). Deleted + recreated with the explicit
   `knn_vector` 1024 mapping (`index-mapping.json`), re-ingested.
2. **On-demand model ID rejected** — Claude 3.5+ needs an **inference profile** ID
   (`us.anthropic.claude-...`), not the bare foundation-model ID.
3. **Model entitlement** — Claude 3.x is Legacy; Claude 4.x Haiku/Sonnet need an **AWS
   Marketplace subscription** (admin-only). Only `us.anthropic.claude-opus-4-5-20251101-v1:0`
   was entitled in this account, so `bedrock_model_id` defaults to it; `iam.tf` gained the
   `inference-profile/` ARN.

**Result:** `POST /query {"question":"What was the Q4 revenue?"}` → `200` with
`"$2,000,000 ... 35% growth"` + `sources:["sample.pdf"]`, matching README Step 7. The canonical
Q4 sample PDF (`create_sample_pdf.py`) was regenerated and uploaded for the demo.

**Caveat:** default model is Opus 4.5 (expensive) only because it is the sole entitled model.
Switch to Haiku 4.5 after an admin completes the Marketplace subscription. The Opus 4.5
entitlement was still propagating during the test (one follow-up call returned "subscription
still being processed — try again after 15 minutes").

Cost warning: OpenSearch `t3.small.search` costs ~$0.036/hr → ~$26/month.
**Run `terraform destroy` immediately after each test session.**

### Update — 26-06-11 (session 4: Free Tier premise + cost efficiency)

**Standing premise for this and every project in the repo: a Free Tier AWS account.**
Cost efficiency is a first-class goal, not an afterthought. Re-evaluated P5 against that:

- **OpenSearch — Free Tier eligible (for now).** The domain is a single-node
  `t3.small.search` with 10GB gp3 EBS (`main.tf`). AWS OpenSearch free tier covers **750
  hrs/month of one `t3.small.search` + 10GB EBS for the first 12 months** — enough for one
  node running 24/7. So the "~$0.86/day / ~$26/month" figure above is the **post-free-tier**
  (or second-node / month-13) cost, *not* what a fresh free-tier account pays. Still
  **`terraform destroy` after each session** — it protects the 750-hr monthly budget, leaves
  headroom for other OpenSearch use, and avoids a surprise bill once the 12 months lapse.
  Minor caveat: free-tier EBS was historically specified as gp2; this domain uses gp3 (still
  "General Purpose", should qualify) — confirm on the Billing → Free Tier page.

- **Bedrock — the real cost, and never free.** Bedrock is **not** in the AWS Free Tier; every
  Titan embedding + Claude generation call is billed per token. This is the only uncontrollable
  P5 cost on a free-tier account. Opus 4.5 (~$5 / $25 per 1M in/out) is the *most expensive*
  Anthropic model and was only the default because it was the **sole entitled model** in this
  account (3.x is Legacy; 4.x Haiku/Sonnet need an admin Marketplace subscription — see ERR-006).
  - **Action taken (this session):** `bedrock_model_id` default switched to the cost-efficient
    `us.anthropic.claude-haiku-4-5-20251001-v1:0` (~$1 / $5 per 1M, ~5× cheaper than Opus).
    **Contingent on the Claude Haiku 4.5 Marketplace subscription being active** — if it isn't,
    generation returns AccessDenied / "subscription required"; fallback is to set
    `bedrock_model_id` back to `us.anthropic.claude-opus-4-5-20251101-v1:0`. Reflected in README
    Step 1 + variables.tf description.
  - **Until then, minimize Bedrock spend:** keep `top_k`/chunk counts low (already `top_k=5`),
    run only the handful of validation queries, and destroy promptly.

- **Everything else is comfortably within Free Tier** at P5's volume: Lambda, S3, DynamoDB
  (on-demand), API Gateway, CloudWatch, SNS. No action needed.

**Net:** under the Free Tier premise, P5's cost discipline is two rules — (1) `terraform
destroy` after every session (OpenSearch hour budget), and (2) default is now Haiku 4.5 — keep
it (revert to Opus only if the Haiku subscription isn't active) and keep query volume small.

---

## Goals

1. ~~**Fix folder nesting**~~ — ✅ already at correct path (`project5-document-engine/main.tf` exists)

2. ~~**Translate README to English**~~ — ✅ done 26-06-10

3. ~~**Deploy and validate**~~ — ✅ done 26-06-11 (session 3). Query API verified returning
   `answer` + `sources` with the `$2,000,000` Q4 answer; see ERR-006 and the
   `26-06-11 [bug] P5 Inference Profile and Model Entitlement Fix` changelog.
   **Still run `terraform destroy` after each session** (OpenSearch cost).

4. **Add design doc** — create `docs/design/p5-document-engine/design.md` following the
   pattern of `docs/design/p4-ai-chatbot/design.md`.
   Verify: file exists and covers architecture, AWS resources, cost note, and reuse of P1–P4 patterns.

5. **Add remote-state backend** — create `project5-document-engine/backend.tf` pointing at the
   same S3 bucket used by P4 (`bootstrap/`), with a distinct `key` (e.g., `p5/terraform.tfstate`).
   Verify: `terraform init` succeeds without local state.

6. **Write changelog entry** — one entry covering deploy/validate result.

---

## Known Blockers

- [x] AWS account activation — confirmed active (Bedrock accessible as of 26-06-10)
- [x] `variables.tf` `suffix` and `alert_email` — already set (`jaehwan-20250608`, `qkrwoghks0717@gmail.com`)
- [x] Bedrock model access (resolved, see ERR-006): the "Model access" page is **retired**.
      Titan `amazon.titan-embed-text-v2:0` auto-enables. Claude generation needs an **inference
      profile** ID + account **entitlement** — 3.x is Legacy, 4.x Haiku/Sonnet need a Marketplace
      subscription (admin). Default is now `us.anthropic.claude-haiku-4-5-20251001-v1:0` (cost);
      requires the Haiku 4.5 subscription active, else fall back to Opus 4.5 (the model that was
      already entitled).
- [ ] Bootstrap S3 state bucket must exist before adding `backend.tf` for P5 (Goal 5)
- [ ] Cost budget (Free Tier account premise): OpenSearch single `t3.small.search` + 10GB is
      Free Tier eligible for 12 months (750 hrs/month) — ~$0.86/day only *after* that or with a
      2nd node. Bedrock is **never** free (per-token); default is now the cheaper
      `claude-haiku-4-5` (~5× under Opus) — needs the Haiku 4.5 Marketplace subscription active,
      else revert to Opus 4.5. **Destroy after each session.** See session-4 update above.

---

## Files to Read First

- `project5-document-engine/README.md` — architecture, deployment steps, and validation checklist
- `project5-document-engine/main.tf` — full infrastructure
- `project5-document-engine/lambda/ingest/index.py` — ingest pipeline (Textract → Bedrock → OpenSearch)
- `project5-document-engine/lambda/query/index.py` — query + RAG response
- `project4-ai-chatbot/backend.tf` — reference for writing P5's backend.tf (Goal 5)
- `docs/design/p4-ai-chatbot/design.md` — reference style for the new P5 design doc (Goal 4)
- `docs/changelog/template.md` — required before writing any changelog entries

---

## PowerShell Deployment Sequence (Goal 3)

Run all commands from `project5-document-engine\` in PowerShell.

### 1. Deploy infrastructure
```powershell
cd C:\Learn\Cloud-Project\project5-document-engine
terraform init
terraform apply
```
> OpenSearch takes **10–15 min** to provision. Wait for `apply` to fully complete.

### 2. Generate sample PDF
```powershell
cd sample_docs
pip install reportlab
python create_sample_pdf.py
cd ..
```

### 3. Create the OpenSearch vector index
> Note: `terraform output -raw step1_create_index | Invoke-Expression` will not work on Windows
> because the output contains bash substitution syntax. Use the explicit PowerShell form below.

```powershell
$ENDPOINT = terraform output -raw opensearch_endpoint
$REGION   = "us-east-1"
$KEY      = aws configure get aws_access_key_id
$SECRET   = aws configure get aws_secret_access_key

curl.exe -X PUT "$ENDPOINT/documents" `
  --aws-sigv4 "aws:amz:${REGION}:es" `
  --user "${KEY}:${SECRET}" `
  -H "Content-Type: application/json" `
  -d '{\"settings\":{\"index\":{\"knn\":true,\"knn.space_type\":\"cosinesimil\"}},\"mappings\":{\"properties\":{\"doc_id\":{\"type\":\"keyword\"},\"source_key\":{\"type\":\"keyword\"},\"chunk_index\":{\"type\":\"integer\"},\"total_chunks\":{\"type\":\"integer\"},\"text\":{\"type\":\"text\",\"analyzer\":\"standard\"},\"word_count\":{\"type\":\"integer\"},\"indexed_at\":{\"type\":\"date\"},\"embedding\":{\"type\":\"knn_vector\",\"dimension\":1024,\"method\":{\"name\":\"hnsw\",\"space_type\":\"cosinesimil\",\"engine\":\"nmslib\"}}}}}'
```
Expected response: `{"acknowledged":true,"shards_acknowledged":true,"index":"documents"}`

### 4. Upload PDF and watch CloudWatch logs
```powershell
$BUCKET = terraform output -raw documents_bucket
aws s3 cp sample_docs\sample.pdf s3://$BUCKET/sample.pdf
aws logs tail /aws/lambda/p5-doc-engine-ingest --follow --region ap-northeast-2
```
> Watch for `[Ingest] ✅ 완료: N개 청크 색인` — this confirms Textract ran successfully.
> Ctrl+C to stop tailing.

### 5. Verify DynamoDB and OpenSearch
```powershell
# Check DynamoDB for status=completed
aws dynamodb scan --table-name p5-doc-engine-documents --region ap-northeast-2

# Check OpenSearch document count
$ENDPOINT = terraform output -raw opensearch_endpoint
$KEY      = aws configure get aws_access_key_id
$SECRET   = aws configure get aws_secret_access_key
curl.exe -X GET "$ENDPOINT/documents/_count" `
  --aws-sigv4 "aws:amz:ap-northeast-2:es" `
  --user "${KEY}:${SECRET}"
```

### 6. Test the query API
```powershell
$API = terraform output -raw query_api_endpoint
curl.exe -X POST $API `
  -H "Content-Type: application/json" `
  -d '{\"question\": \"What was the Q4 revenue?\"}'
```
Expected: `{"answer": "...", "sources": [{"chunk_id": "...", "score": 0.9X}]}`

### 7. Destroy immediately after testing
```powershell
aws s3 rm s3://$BUCKET --recursive
terraform destroy
```
> Confirm OpenSearch is gone: AWS Console → OpenSearch → Domains → `p5-doc-engine-search` must not appear.

---

## Out of Scope

- API key auth on the query endpoint (P4 used API Gateway keys; P5 currently has none — add later).
- Multi-file upload UI (S3 console / CLI upload is sufficient for now).
- P6 planning.
