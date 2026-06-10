# 26-06-11 [upgrade] P2 Textract Replaced with pypdf

**Type:** upgrade
**Branch / Commit:** Testo / (uncommitted)

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project2-serverless-pipeline/lambda/extractor/index.py` | `extract_pdf` (was `extract_pdf_async`), module imports | Replaced Textract async (`start_document_text_detection` + polling + pagination) with pypdf `PdfReader`; removed `textract` boto3 client and `import time`; added `import io`, `import pypdf` |
| `project2-serverless-pipeline/iam.tf` | `aws_iam_policy.extractor_custom` | Removed all 4 `textract:*` actions; kept `rekognition:DetectLabels`/`DetectText` |
| `project2-serverless-pipeline/main.tf` | `archive_file.extractor`, new `terraform_data.install_extractor_deps`, `aws_lambda_function.extractor` | Switched extractor zip from `source_file` to `source_dir`; added `uv pip install` step; updated memory comment (no longer mentions Textract) |
| `project2-serverless-pipeline/lambda/extractor/requirements.txt` | *(new)* | Declares `pypdf>=4.0.0` |
| `project2-serverless-pipeline/lambda/extractor/.gitignore` | *(new)* | Ignores uv-installed package dirs |
| `README.md` | P2 service table | Extractor row + processed-bucket row now say pypdf, not Textract |
| `project2-serverless-pipeline/README.md` | Cost table, Step 4, Common Errors | Textract row → pypdf (free, in-Lambda); Step 4 heading + note; AccessDenied/empty-text error entries rewritten |
| `project2-serverless-pipeline/file-structure.md` | tree, key relationships | Extractor note + new requirements.txt; Rekognition-only `Resource:"*"` note |
| `docs/design/p2-serverless-pipeline/design.md` | Purpose, Resource Inventory | PDF path is pypdf; added ERR-003 rationale note |

## Why Changed

Amazon Textract is unusable on this AWS account — it returns `SubscriptionRequiredException`
in every region (confirmed in `us-east-1` via direct CLI call during P5 bring-up). This is an
account-level subscription restriction with no self-service resolution (ERR-003). P2's Extractor
Lambda used Textract for the PDF path, so PDF uploads could never succeed on this account. P5
already hit this and moved to pypdf; P2 now follows the same decision so the pipeline actually
works. The image path (Rekognition) is unaffected and unchanged.

## Contents Diff

**`lambda/extractor/index.py` — PDF extraction**
```python
# Before — Textract async job: start → poll JobStatus every 5s → paginate Blocks
def extract_pdf_async(bucket, key):
    start_response = textract.start_document_text_detection(
        DocumentLocation={"S3Object": {"Bucket": bucket, "Name": key}})
    job_id = start_response["JobId"]
    while status == "IN_PROGRESS":
        time.sleep(5)
        ... get_document_text_detection(JobId=job_id) ...
    # paginate Blocks → LINE/WORD text
    return {"type": "pdf", "text": "\n".join(lines), "word_count": len(words), ...}

# After — read bytes from S3, extract embedded text with pypdf
def extract_pdf(bucket, key):
    obj = s3.get_object(Bucket=bucket, Key=key)
    reader = pypdf.PdfReader(io.BytesIO(obj["Body"].read()))
    pages = [t for page in reader.pages if (t := page.extract_text())]
    full_text = "\n".join(pages)
    return {"type": "pdf", "text": full_text,
            "word_count": len(full_text.split()), "page_count": len(reader.pages), ...}
```

**`iam.tf` — extractor policy AI block**
```hcl
# Before
Action = ["textract:DetectDocumentText", "textract:AnalyzeDocument",
          "textract:StartDocumentTextDetection", "textract:GetDocumentTextDetection",
          "rekognition:DetectLabels", "rekognition:DetectText"]

# After
Action = ["rekognition:DetectLabels", "rekognition:DetectText"]
```

**`main.tf` — extractor packaging**
```hcl
# Before — zipped index.py only
data "archive_file" "extractor" {
  source_file = "${path.module}/lambda/extractor/index.py"
  ...
}

# After — uv installs pypdf into the dir, whole dir zipped
resource "terraform_data" "install_extractor_deps" {
  triggers_replace = [filemd5("${path.module}/lambda/extractor/requirements.txt")]
  provisioner "local-exec" {
    command = "uv pip install -r ${path.module}/lambda/extractor/requirements.txt --target ${path.module}/lambda/extractor --quiet"
  }
}
data "archive_file" "extractor" {
  source_dir = "${path.module}/lambda/extractor"
  depends_on = [terraform_data.install_extractor_deps]
  ...
}
```

## Improvements

- P2's PDF path works on this account (no Textract subscription dependency).
- Least privilege: extractor role dropped 4 Textract actions; Rekognition-only now.
- Less data exposure: removed full-Textract-response `print(json.dumps(...))`; pypdf path logs a filename.
- Simpler control flow: no async job polling loop or pagination — synchronous in-Lambda parse.
- Consistent with P5 (same pypdf + uv packaging pattern).

## Performance Impact

- PDF extraction latency drops sharply: Textract async polled `JobStatus` every 5s (minimum
  ~5–10s per PDF plus job startup); pypdf parses in-process in well under a second for small PDFs.
- Lambda zip grows from index.py only (~few KB) to index.py + pypdf (~450 KB) — far under the 250 MB limit.
- Cold start: pypdf import adds ~50ms.
- Removed `time.sleep` polling eliminates idle billed Lambda duration during Textract jobs.

## Agents Consulted

security

## Findings Addressed

none (no BLOCK/WARN — change is a net least-privilege + logging improvement)

## Findings Deferred

- **[INFO] Rekognition `Resource:"*"`** — required by the AWS API (no resource-level ARNs); documented in `iam.tf`. Not fixable.
- **[INFO] `pypdf>=4.0.0` unpinned upper bound** installed via apply-time `uv pip install` — supply-chain surface. Matches the accepted P5 precedent; deferred for consistency.
- **pypdf does no OCR** — scanned / image-only PDFs yield empty text (documented in README). Acceptable; Textract's OCR is not available on this account anyway.
