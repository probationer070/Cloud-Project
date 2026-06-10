# Project 2: Serverless Data Processing Pipeline

> **Standalone project** — P1, P3, and P4 do not need to be deployed.

## Architecture

```
File upload (S3 ObjectCreated  or  POST /upload)
    → Router Lambda (detects file extension)
         ├─ csv / json  → Structured SQS   → Parser Lambda    → DynamoDB
         ├─ pdf / image → Unstructured SQS → Extractor Lambda → S3 processed
         └─ unknown     → S3 quarantine
    (3 failures → DLQ → CloudWatch alarm → SNS → email)
```

## Estimated Cost

| Service | Free Tier | Note |
|---------|-----------|------|
| Lambda | 1M requests/mo | free |
| S3 (3 buckets) | 5 GB / 20,000 GET | free |
| SQS | 1M requests/mo | free |
| DynamoDB | 25 GB / PAY_PER_REQUEST | free |
| pypdf (PDF text) | in-Lambda, free | No AWS service — runs inside the Extractor Lambda (Textract is unavailable on this account, see ERR-003) |
| Rekognition | 5,000 images/mo | $1/1,000 images over limit |

> ~$0–1/mo at test scale.

---

## Deployment Steps

### Step 1. Edit variables.tf

```hcl
suffix      = "yourname-20260527"  # ← unique suffix for S3 bucket names (required)
alert_email = "your@email.com"     # ← alarm notification email (required)
```

### Step 2. Deploy Infrastructure

```powershell
cd project2-serverless-pipeline
terraform init
terraform plan
terraform apply
```

After `terraform apply` completes, note the outputs:

```
ingestion_bucket  = "p2-pipeline-ingestion-..."
processed_bucket  = "p2-pipeline-processed-..."
quarantine_bucket = "p2-pipeline-quarantine-..."
api_endpoint      = "https://xxxxx.execute-api.ap-northeast-2.amazonaws.com/v1/upload"
dynamodb_table    = "p2-pipeline-records"
dashboard_url     = "https://..."
```

### Step 3. Confirm SNS Email Subscription

An **"AWS Notification - Subscription Confirmation"** email will arrive at `alert_email`.
**Click "Confirm subscription".**

---

## Test Scenarios

> Run `terraform output` to see the test commands pre-filled with your actual bucket names.

### 1. CSV Upload → DynamoDB

```powershell
# Run the test_csv_upload output command
aws s3 cp sample_data/test.csv s3://[ingestion_bucket]/test.csv
```

Wait 5–10 seconds, then verify DynamoDB:

```powershell
# Run the check_dynamodb output command
aws dynamodb scan --table-name p2-pipeline-records --region ap-northeast-2
```

### 2. JSON Upload → DynamoDB

```powershell
aws s3 cp sample_data/test.json s3://[ingestion_bucket]/test.json
# Verify another record appears in DynamoDB
```

### 3. Unknown Format → Quarantine

```powershell
# Run the test_unknown_upload output command
aws s3 cp sample_data/test.xyz s3://[ingestion_bucket]/test.xyz

# Verify file moved to quarantine bucket
# Run the check_quarantine output command
aws s3 ls s3://[quarantine_bucket]/ --recursive
```

### 4. PDF Upload → pypdf Text Extraction

```powershell
# Run the test_pdf_upload output command (prepare a PDF first)
aws s3 cp sample_data/test.pdf s3://[ingestion_bucket]/test.pdf

# Verify JSON result in processed bucket (allow a few seconds)
aws s3 ls s3://[processed_bucket]/results/ --recursive
```

> PDF text is extracted **in-Lambda with pypdf** — Amazon Textract is unavailable on this
> account (account-level subscription restriction, no self-service fix; see ERR-003). pypdf reads
> embedded text from any text-based PDF; scanned / image-only PDFs return no text (pypdf does no OCR).

### 5. API Gateway Upload Test

**Windows (PowerShell):**
```powershell
# Use the api_endpoint value from terraform output
Invoke-RestMethod `
  -Uri "[api_endpoint]" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"filename": "api-test.json", "content": "{\"key\": \"value\"}"}'
```
**Linux / macOS:**
```bash
# Use the api_endpoint value from terraform output
curl -X POST "[api_endpoint]" \
  -H "Content-Type: application/json" \
  -d '{"filename": "api-test.json", "content": "{\"key\": \"value\"}"}'
```
**Windows (curl.exe):**
```powershell
curl.exe -X POST "[api_endpoint]" `
  -H "Content-Type: application/json" `
  -d '{\"filename\": \"api-test.json\", \"content\": \"{\\\"key\\\": \\\"value\\\"}\"}'
```

### 6. CloudWatch Dashboard

```
Open dashboard_url from terraform output
→ Check Lambda invocations, error count, SQS queue depth, DLQ depth
```

---

## Validation Checklist

- [ ] `terraform output` shows bucket names and `api_endpoint`
- [ ] SNS subscription confirmation email received → clicked "Confirm subscription"
- [ ] CSV upload → DynamoDB record created
- [ ] JSON upload → DynamoDB record added
- [ ] `.xyz` upload → file appears in quarantine bucket
- [ ] PDF upload → JSON result file in processed bucket
- [ ] DLQ is empty (no processing failures)
- [ ] CloudWatch dashboard shows Lambda invocation graph

---

## Common Errors

**Lambda AccessDenied**
→ Check the Lambda policy in `iam.tf`
→ Rekognition requires `Resource = "*"`

**SQS trigger not firing**
→ Check the Event Source Mapping status:
```powershell
aws lambda list-event-source-mappings --function-name p2-pipeline-parser
```

**PDF result has empty text**
→ pypdf only reads embedded text — it does no OCR
→ A scanned / image-only PDF yields no text; use a text-based PDF

---

## Destroy Resources

```powershell
# 1. Empty all 3 S3 buckets (destroy fails if files remain)
aws s3 rm s3://[ingestion_bucket] --recursive
aws s3 rm s3://[processed_bucket] --recursive
aws s3 rm s3://[quarantine_bucket] --recursive

# 2. Destroy Terraform resources
terraform destroy
```
