# Project 5: Intelligent Document Analysis Engine (RAG-based)

> **Standalone project** — P1–P4 do NOT need to be deployed. P5 creates all its own AWS resources independently.
>
> **Prerequisites:**
> 1. **AWS account must be fully activated** — payment method verified ($1 hold), identity verification complete, and a support plan selected (Basic/free is fine). If any step is pending, all premium services (Bedrock, OpenSearch) will be blocked. AWS Console → Account to check. Activation can take up to 24 hours.
> 2. **Bedrock models** are reached cross-region in `us-east-1` regardless of `aws_region`. AWS has retired the old "Model access" page — serverless models now auto-enable on first `InvokeModel`, so there is no console grant step. For Anthropic Claude, a first-time account may need to submit a one-time use-case form (Bedrock console → Model catalog). Invoke permission itself is governed by the Lambda IAM role in `iam.tf`.

## ⚠️ Cost Warning

| Service | Free Tier | Note |
|---------|-----------|------|
| OpenSearch (t3.small.search) | none | **~$0.036/hr → ~$0.86/day** |
| Lambda | 1M requests/mo | free |
| S3 | 5 GB | free |
| DynamoDB | 25 GB | free |
| Bedrock (Titan Embeddings) | none | **~$0.0001/1K tokens** |
| Bedrock (Claude generation) | none (never Free Tier — billed per token) | Default **Haiku 4.5** (~$1/$5 per 1M in/out) for cost efficiency. Requires the Claude Haiku 4.5 **Marketplace subscription** (admin) — if not yet subscribed, fall back to **Opus 4.5** (~$5/$25 per 1M, ~5× pricier). See Step 1. |

> **OpenSearch is the cost driver.** Run `terraform destroy` immediately after testing — leaving it running overnight costs ~$0.86.

---

## Architecture (RAG Pattern)

```
[Document Upload]
  PDF → S3 → Lambda(Ingest)
               ↓ pypdf       ↓ Chunk Splitting
               Text Extract  500-word chunks
                    ↓
              Titan Embeddings  (text → 1024-dim vectors)
                    ↓
              OpenSearch Index (vector storage)
                    ↓
              DynamoDB metadata storage

[Question → Answer]
  Question → API Gateway → Lambda(Query)
                             ↓
                       Titan Embeddings (vectorize question)
                             ↓
                       OpenSearch kNN search (top-5 similar chunks)
                             ↓
                       Bedrock Claude (generate answer from chunks)
                             ↓
                       Answer + source references returned
```

---

## File Structure

```
project5-document-engine/
├── main.tf                      # S3, OpenSearch, DynamoDB, Lambda×2, API GW
├── iam.tf                       # Least-privilege IAM per Lambda
├── variables.tf
├── outputs.tf                   # Step-by-step test commands
└── lambda/
    ├── ingest/
    │   ├── index.py             # Document processing pipeline
    │   └── requirements.txt    # pypdf — bundled by terraform apply
    └── query/
        └── index.py             # Semantic search + answer generation
└── sample_docs/
    └── create_sample_pdf.py     # Script to generate test PDF
```

---

## Lambda Packaging

Both Lambda functions are deployed as **zip packages**, not container images. Dockerfiles exist in each Lambda directory but are **not used** by Terraform.

| | Ingest | Query |
|---|---|---|
| Deployment method | zip (`archive_file`) | zip (`archive_file`) |
| Dependency install | `uv pip install` runs locally during `terraform apply` | none (no extra deps) |
| Dockerfile | present — unused | present — unused |

**How zip deployment works (Terraform):**
1. `terraform_data` runs `uv pip install -r requirements.txt --target lambda/ingest/` on your local machine
2. `archive_file` zips the entire `lambda/ingest/` directory (code + installed packages)
3. The zip is uploaded to Lambda as the deployment package

**What the Dockerfiles are for:**  
They are prepared for a future switch to container image deployment (`package_type = "Image"` + ECR). To use them, `main.tf` would need to change from `filename =` to `image_uri =` and add an ECR push step. Until then, the Dockerfiles are inert.

---

## Deployment Steps

### Step 1. Bedrock Model Access

AWS **retired the Bedrock "Model access" page.** Access now depends on three things, not a
console toggle:

**Embedding model — `amazon.titan-embed-text-v2:0`:** serverless, auto-enables on first
`InvokeModel`. Nothing to do.

**Generation model (Claude) — two real gates:**

1. **Inference profile required.** Claude 3.5 and newer cannot be invoked by their bare
   `foundation-model` ID — you must use a region-prefixed **inference profile** ID
   (`us.anthropic.claude-...`). `bedrock_model_id` in `variables.tf` is already set to one.
   List what your account has: `aws bedrock list-inference-profiles --region us-east-1`.
2. **Account entitlement.** Not every Claude model is invocable:
   - Claude **3.x** models are **Legacy** (denied for accounts with no recent usage).
   - Claude **4.x Haiku / Sonnet** are served via **AWS Marketplace** and need a one-time
     subscription performed by an **admin** with `aws-marketplace:Subscribe` /
     `ViewSubscriptions`. The Lambda role cannot self-subscribe.

   This project defaults to **`us.anthropic.claude-haiku-4-5-20251001-v1:0`** — the cost-efficient
   choice for the Free Tier premise (~5× cheaper than Opus). It requires the Claude Haiku 4.5
   **Marketplace subscription** (admin) to be active; if it is not, generation fails with an
   AccessDenied / "subscription required" error. In that case fall back to the already-entitled
   **`us.anthropic.claude-opus-4-5-20251101-v1:0`** (more expensive) until the subscription lands.

> Verify a model is actually entitled before wiring it in:
> ```bash
> printf '{"anthropic_version":"bedrock-2023-05-31","max_tokens":20,"messages":[{"role":"user","content":"Say OK"}]}' > t.json
> aws bedrock-runtime invoke-model --model-id us.anthropic.claude-haiku-4-5-20251001-v1:0 \
>   --body fileb://t.json --content-type application/json --region us-east-1 out.json && cat out.json
> ```
> Invoke permission itself comes from the Lambda's IAM role (`bedrock:InvokeModel` on both the
> `inference-profile/` and `foundation-model/` ARNs in `iam.tf`), not a console toggle.

### Step 2. Edit variables.tf

```hcl
suffix      = "yourname-20250527"   # ← unique suffix for resource names (required)
alert_email = "your@email.com"      # ← email for SNS alerts (required)
```

### Step 3. Deploy Infrastructure

**Windows (PowerShell):**
```powershell
cd project5-document-engine
terraform init
terraform plan
terraform apply
```
**Linux / macOS:**
```bash
cd project5-document-engine
terraform init
terraform plan
terraform apply
```

> OpenSearch takes **10–15 minutes** to provision. Wait for `terraform apply` to complete fully before the next step.
>
> `terraform apply` also runs `pip install` automatically to bundle pypdf into the Ingest Lambda.

### Step 4. Create the OpenSearch Index

> ⚠️ **Create the index BEFORE uploading any document (Step 5).** If the Ingest Lambda writes a
> chunk first, OpenSearch auto-creates `documents` with a dynamic mapping where `embedding` is a
> plain `float` array, not `knn_vector` — and every query then fails with **HTTP 400**. If that
> happens, delete and recreate the index (see Common Errors), then re-upload. See ERR-006.

**Windows (PowerShell)** — the `step1_create_index` output is bash syntax that won't run in
PowerShell, so use the bundled `index-mapping.json` (1024-dim `knn_vector` mapping):
```powershell
$ENDPOINT = terraform output -raw opensearch_endpoint
$KEY = aws configure get aws_access_key_id
$SECRET = aws configure get aws_secret_access_key
curl.exe -X PUT "$ENDPOINT/documents" `
  --aws-sigv4 "aws:amz:us-east-1:es" --user "${KEY}:${SECRET}" `
  -H "Content-Type: application/json" -d "@index-mapping.json"
```
**Linux / macOS:**
```bash
eval "$(terraform output -raw step1_create_index)"
```

Expected response:
```json
{"acknowledged": true, "shards_acknowledged": true, "index": "documents"}
```

### Step 5. Generate and Upload a Test PDF

**Windows (PowerShell):**
```powershell
cd sample_docs
pip install reportlab
python create_sample_pdf.py
cd ..

$BUCKET = terraform output -raw documents_bucket
aws s3 cp sample_docs\sample.pdf s3://$BUCKET/sample.pdf
aws logs tail /aws/lambda/p5-doc-engine-ingest --follow --region us-east-1
```
**Linux / macOS:**
```bash
cd sample_docs
pip install reportlab
python3 create_sample_pdf.py
cd ..

BUCKET=$(terraform output -raw documents_bucket)
aws s3 cp sample_docs/sample.pdf s3://$BUCKET/sample.pdf
aws logs tail /aws/lambda/p5-doc-engine-ingest --follow --region us-east-1
```

Expected log output:
```
[Ingest] 처리 시작: s3://[bucket]/sample.pdf → doc_id=xxxxxxxx
[Ingest] 텍스트 추출 완료: NNN자
[Ingest] 청크 분할 완료: N개
[Ingest] ✅ 완료: N개 청크 색인
```

### Step 6. Verify Processing

Check DynamoDB for `status=completed`:

**Windows (PowerShell):**
```powershell
aws dynamodb scan `
  --table-name p5-doc-engine-documents `
  --region us-east-1 `
  --query "Items[*].{status:status.S, chunks:chunk_count.N, source:source_key.S}" `
  --output table
```
**Linux / macOS:**
```bash
aws dynamodb scan \
  --table-name p5-doc-engine-documents \
  --region us-east-1 \
  --query "Items[*].{status:status.S, chunks:chunk_count.N, source:source_key.S}" \
  --output table
```

Expected: a row with `status=completed` and `chunks > 0`.

Check OpenSearch document count:

**Windows (PowerShell):**
```powershell
terraform output -raw step4_check_index | & "$env:PROGRAMFILES\Git\usr\bin\bash.exe"
```
**Linux / macOS:**
```bash
eval "$(terraform output -raw step4_check_index)"
```

Expected: `{"count": N, ...}` where N > 0.

### Step 7. Query Testing

**Windows (PowerShell):**
```powershell
$API = terraform output -raw query_api_endpoint
Invoke-RestMethod -Uri $API -Method POST -ContentType "application/json" `
  -Body '{"question": "What was the Q4 revenue?"}'
```
**Linux / macOS:**
```bash
API=$(terraform output -raw query_api_endpoint)
curl -X POST $API \
  -H "Content-Type: application/json" \
  -d '{"question": "What was the Q4 revenue?"}'
```

Expected response:
```json
{
  "answer": "According to the document, Q4 Revenue hit 2 million...",
  "sources": [{"chunk_id": "sample.pdf-chunk-3", "score": 0.94}]
}
```

**Key semantic search test** — verify different phrasing retrieves the same content:

**Windows (PowerShell):**
```powershell
Invoke-RestMethod -Uri $API -Method POST -ContentType "application/json" `
  -Body '{"question": "How much did the cloud migration save?"}'
```
**Linux / macOS:**
```bash
curl -X POST $API \
  -H "Content-Type: application/json" \
  -d '{"question": "How much did the cloud migration save?"}'
```

Expected: Claude retrieves AWS-related chunks and generates an answer even though the question phrasing differs from the document text. This confirms the RAG vector search is working.

---

## Validation Checklist

- [ ] `terraform output` shows `query_api_endpoint` and `documents_bucket`
- [ ] OpenSearch index created — `step1_create_index` returns `"acknowledged": true`
- [ ] PDF uploaded → Ingest Lambda triggered automatically (CloudWatch logs confirm)
- [ ] DynamoDB record shows `status=completed` with `chunk_count > 0`
- [ ] OpenSearch document count > 0 (`step4_check_index`)
- [ ] Query API returns `answer` + `sources` array
- [ ] Semantic search works — different phrasing retrieves the same content

---

## Common Errors

**Ingest Lambda exits with no chunks**
→ Check CloudWatch logs for the specific error.
→ Verify the PDF is not password-protected or empty.

**Query API returns 500 with "no documents indexed"**
→ OpenSearch index may not exist. Re-run the Step 4 index creation command.
→ Run `step4_check_index` to confirm document count > 0.

**Query API returns 500 wrapping `HTTP Error 400: Bad Request`**
→ The OpenSearch kNN search was rejected — almost always because `embedding` is mapped as
  `float`, not `knn_vector` (the index was auto-created by an ingest write before Step 4).
  Check it: `GET /documents/_mapping` → `embedding` should be `"type":"knn_vector"`.
→ Fix: delete and recreate the index with the correct mapping, then re-upload the PDF:
  ```powershell
  $ENDPOINT = terraform output -raw opensearch_endpoint
  $KEY = aws configure get aws_access_key_id; $SECRET = aws configure get aws_secret_access_key
  curl.exe -X DELETE "$ENDPOINT/documents" --aws-sigv4 "aws:amz:us-east-1:es" --user "${KEY}:${SECRET}"
  curl.exe -X PUT "$ENDPOINT/documents" --aws-sigv4 "aws:amz:us-east-1:es" --user "${KEY}:${SECRET}" `
    -H "Content-Type: application/json" -d "@index-mapping.json"
  ```
  See ERR-006.

**Bedrock returns `ValidationException ... on-demand throughput isn't supported ... inference profile`**
→ Claude 3.5+ cannot be called by its bare model ID. Set `bedrock_model_id` to an inference
  profile ID (`us.anthropic.claude-...`) and re-run `terraform apply`. List available profiles:
  `aws bedrock list-inference-profiles --region us-east-1`. See ERR-006.

**Bedrock returns `AccessDeniedException`**
→ Not a console "model access" issue (that page is retired). Two causes:
  1. **IAM** — the Lambda role must allow `bedrock:InvokeModel` on both the `inference-profile/`
     and `foundation-model/` ARNs in `iam.tf` (policy globs the Claude family `anthropic.claude*`).
  2. **Marketplace subscription** — `...required AWS Marketplace actions (aws-marketplace:Subscribe)`
     means the model (e.g. the default Claude Haiku 4.5) needs a one-time subscription by an
     **admin**; the Lambda role cannot self-subscribe. Either have an admin subscribe, or fall
     back to the already-entitled `us.anthropic.claude-opus-4-5-20251101-v1:0`. See Step 1 and ERR-006.

**Bedrock returns `ResourceNotFoundException ... marked by provider as Legacy`**
→ The configured `bedrock_model_id` is a retired model (Claude 3.x). Switch to an entitled active
  model — this project defaults to `us.anthropic.claude-haiku-4-5-20251001-v1:0` (Opus 4.5 as
  fallback) — and re-run `terraform apply`. See ERR-005 and ERR-006.

**pypdf extracts empty text**
→ The PDF may be a scanned image (no embedded text). pypdf only extracts embedded text — use a PDF generated with `create_sample_pdf.py` for testing.

**`terraform apply` fails with OpenSearch domain already exists**
→ A prior `terraform destroy` may not have completed. Check AWS Console → OpenSearch → Domains.
→ OpenSearch domain deletion can take 5–10 minutes after `terraform destroy`.

---

## Destroy Resources

> **Run this immediately after testing — OpenSearch costs ~$0.86/day.**

**Windows (PowerShell):**
```powershell
$BUCKET = terraform output -raw documents_bucket
aws s3 rm s3://$BUCKET --recursive
terraform destroy
```
**Linux / macOS:**
```bash
BUCKET=$(terraform output -raw documents_bucket)
aws s3 rm s3://$BUCKET --recursive
terraform destroy
```

After `terraform destroy` completes, confirm OpenSearch deletion in the AWS Console — OpenSearch domain deletion is asynchronous and can take several minutes:
```
AWS Console → OpenSearch → Domains → confirm "p5-doc-engine" is gone
https://us-east-1.console.aws.amazon.com/esv3/home?region=us-east-1
```

---

## What is RAG?

RAG (Retrieval-Augmented Generation) is a pattern where an AI answers questions by
**finding evidence in real documents** rather than relying solely on training data.

```
Standard AI: answers from training knowledge → risk of hallucination
RAG:         retrieves documents → grounds answer in evidence → higher accuracy
```

How P5 implements this:
1. Document → vector embedding (encode meaning as numbers)
2. Question → vector embedding
3. Find related paragraphs by vector similarity
4. Claude generates an answer grounded in the retrieved paragraphs
