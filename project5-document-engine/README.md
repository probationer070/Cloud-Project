# Project 5: Intelligent Document Analysis Engine (RAG-based)

> **Standalone project** — P1–P4 do NOT need to be deployed. P5 creates all its own AWS resources independently.
>
> **Prerequisites:**
> 1. **AWS account must be fully activated** — payment method verified ($1 hold), identity verification complete, and a support plan selected (Basic/free is fine). If any step is pending, all premium services (Bedrock, OpenSearch) will be blocked. AWS Console → Account to check. Activation can take up to 24 hours.
> 2. **Bedrock model access** must be enabled in `us-east-1` before deploying (Bedrock calls are cross-region to us-east-1 regardless of `aws_region`).

## ⚠️ Cost Warning

| Service | Free Tier | Note |
|---------|-----------|------|
| OpenSearch (t3.small.search) | none | **~$0.036/hr → ~$0.86/day** |
| Lambda | 1M requests/mo | free |
| S3 | 5 GB | free |
| DynamoDB | 25 GB | free |
| Bedrock (Titan Embeddings) | none | **~$0.0001/1K tokens** |
| Bedrock (Claude Haiku) | none | **~$0.00025/1K input tokens** |

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

### Step 1. Enable Bedrock Model Access

In the AWS Console (region: **us-east-1**), request access to both models:
- `amazon.titan-embed-text-v2:0`
- `anthropic.claude-3-5-haiku-20241022-v1:0`

> Models take a few minutes to activate. Confirm status shows **"Access granted"** before proceeding.

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

**Windows (PowerShell):**
```powershell
terraform output -raw step1_create_index
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

**Bedrock returns `AccessDeniedException`**
→ Model access was not granted in `us-east-1`. Check the AWS Console → Bedrock → Model access.
→ Confirm the Lambda IAM role has `bedrock:InvokeModel` in `iam.tf`. The policy globs the
  Claude family (`anthropic.claude*`) — a version-specific glob would miss `claude-3-5-haiku`.

**Bedrock returns `ResourceNotFoundException ... marked by provider as Legacy`**
→ The configured `bedrock_model_id` is a retired model. Set it to an active model (default is
  `anthropic.claude-3-5-haiku-20241022-v1:0`) and re-run `terraform apply`. See ERR-005.

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
