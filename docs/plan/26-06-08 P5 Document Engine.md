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

**Goal 3 (validate) is still OPEN.** Remaining blocker: Bedrock **model access** for Claude
3.5 Haiku must be granted in the console (`us-east-1` → Bedrock → Model access). This is
separate from the IAM fix. Once granted and `terraform apply` has pushed the new model env
var, re-run Step 6/7 and confirm the query API returns `answer` + `sources`.

Cost warning: OpenSearch `t3.small.search` costs ~$0.036/hr → ~$26/month.
**Run `terraform destroy` immediately after each test session.**

---

## Goals

1. ~~**Fix folder nesting**~~ — ✅ already at correct path (`project5-document-engine/main.tf` exists)

2. ~~**Translate README to English**~~ — ✅ done 26-06-10

3. **Deploy and validate** — run the full PowerShell deployment sequence below. All seven
   checklist items in `project5-document-engine/README.md` must be checked off.
   **Run `terraform destroy` when done.**
   Verify: CloudWatch logs show `[Ingest] ✅ 완료: N개 청크 색인` and query API returns `answer` + `sources`.

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
- [ ] AWS Bedrock model access in `us-east-1`: `amazon.titan-embed-text-v2:0` and
      `anthropic.claude-3-5-haiku-20241022-v1:0` — verify "Access granted" in Bedrock console before `terraform apply` (Claude 3 Haiku retired — see ERR-005)
- [ ] Bootstrap S3 state bucket must exist before adding `backend.tf` for P5 (Goal 5)
- [ ] Cost budget: OpenSearch runs at ~$0.86/day — destroy immediately after testing

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
