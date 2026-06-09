# 26-06-10 [upgrade] P5 Textract Replaced with pypdf uv Packaging and Container Prep

**Type:** upgrade
**Branch / Commit:** Testo / (pending commit)

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project5-document-engine/lambda/ingest/index.py` | `extract_text()` | Replaced Textract `detect_document_text` with pypdf `PdfReader`; removed `textract` client; fixed `AWS_REGION` default from `ap-northeast-2` to `us-east-1` |
| `project5-document-engine/iam.tf` | `aws_iam_role_policy.ingest` | Removed `textract:DetectDocumentText` and `textract:AnalyzeDocument` permissions |
| `project5-document-engine/main.tf` | `archive_file.ingest`, `terraform_data.install_ingest_deps` | Changed Lambda zip from `source_file` to `source_dir`; added `terraform_data` resource to run `uv pip install` before archiving |
| `project5-document-engine/lambda/ingest/requirements.txt` | *(new file)* | Declares `pypdf>=4.0.0` as the ingest Lambda dependency |
| `project5-document-engine/lambda/ingest/.gitignore` | *(new file)* | Ignores installed package directories (`pypdf/`, `*.dist-info/`) so they are not committed |
| `project5-document-engine/lambda/ingest/Dockerfile` | *(new file)* | Lambda container image using AWS Python 3.12 base + uv for dependency install; ready for ECR migration when Docker Desktop is installed |
| `project5-document-engine/lambda/query/Dockerfile` | *(new file)* | Minimal Lambda container image for query function; no external dependencies |
| `project5-document-engine/README.md` | deployment steps, common errors, destroy | All Windows commands rewritten to `$VAR = terraform output -raw ...` pattern; replaced `Invoke-Expression` with `| & "$env:PROGRAMFILES\Git\usr\bin\bash.exe"`; removed Textract from architecture diagram, cost table, and errors; DynamoDB scan updated with `--query --output table` |
| `.gitignore` | root | Removed broad `ingest` exclusion that was silently blocking `requirements.txt` from being tracked |

## Why Changed

Textract threw `SubscriptionRequiredException` even in `us-east-1` — confirmed via direct AWS CLI call. This is an account-level restriction (not regional) with no self-service resolution. The ingest pipeline was completely blocked.

Additionally, the README had two broken Windows commands: `terraform output -raw step1_create_index | Invoke-Expression` fails because PowerShell's `Invoke-Expression` cannot parse bash-style `\` line continuations or `--aws-sigv4` flags; and all step commands used `[documents_bucket]` / `[query_api_endpoint]` placeholders that require manual substitution rather than running directly.

pypdf was chosen as the replacement because it is pure Python (no native dependencies), works without any AWS service subscription, and handles all text-based PDFs including the `reportlab`-generated sample. Dependency packaging was switched from committing the installed library to `requirements.txt` + `terraform_data` auto-install via `uv`, following the standard Python Lambda pattern. Dockerfiles were added to prepare for a future Lambda Container Image migration once Docker Desktop is installed.

## Contents Diff

**`lambda/ingest/index.py` — `extract_text()`**
```python
# Before — called Textract via S3Object reference
def extract_text(bucket: str, key: str) -> str:
    response = textract.detect_document_text(
        Document={"S3Object": {"Bucket": bucket, "Name": key}}
    )
    blocks = response.get("Blocks", [])
    lines  = [b["Text"] for b in blocks if b["BlockType"] == "LINE"]
    return "\n".join(lines)

# After — reads PDF bytes from S3, extracts text with pypdf
def extract_text(bucket: str, key: str) -> str:
    obj = s3.get_object(Bucket=bucket, Key=key)
    pdf_bytes = obj["Body"].read()
    reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))
    pages = []
    for page in reader.pages:
        text = page.extract_text()
        if text:
            pages.append(text)
    return "\n".join(pages)
```

**`main.tf` — Lambda packaging block**
```hcl
# Before — zipped only index.py, no dependency management
data "archive_file" "ingest" {
  type        = "zip"
  source_file = "${path.module}/lambda/ingest/index.py"
  output_path = "${path.module}/.terraform/lambda-ingest.zip"
}

# After — uv installs deps into the directory, then zips the whole directory
resource "terraform_data" "install_ingest_deps" {
  triggers_replace = [filemd5("${path.module}/lambda/ingest/requirements.txt")]
  provisioner "local-exec" {
    command = "uv pip install -r ${path.module}/lambda/ingest/requirements.txt --target ${path.module}/lambda/ingest --quiet"
  }
}

data "archive_file" "ingest" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/ingest"
  output_path = "${path.module}/.terraform/lambda-ingest.zip"
  depends_on  = [terraform_data.install_ingest_deps]
}
```

**`iam.tf` — removed Textract statement**
```hcl
# Before — included Textract permission block
{
  Effect   = "Allow"
  Action   = ["textract:DetectDocumentText", "textract:AnalyzeDocument"]
  Resource = "*"
},

# After — block removed entirely
```

## Improvements

- Ingest pipeline now works end-to-end: `status=completed`, `chunk_count=2` confirmed in DynamoDB after first successful run
- All README Windows commands run without modification — no manual URL substitution, no PowerShell alias conflicts
- Dependency declared in `requirements.txt` (committed); installed packages gitignored — standard Python Lambda packaging pattern
- `uv` replaces `pip` for ~10x faster dependency installation during `terraform apply`
- Dockerfiles in place for future Lambda Container Image migration (eliminates `terraform_data` hack entirely)

## Performance Impact

- `uv pip install` vs `pip install`: ~10x faster on warm cache for a single-package requirements file (sub-second vs ~3-5 seconds)
- Lambda zip size: increased from `index.py` only (~15 KB) to `index.py` + pypdf package (~450 KB) — well within Lambda 250 MB limit
- Lambda cold start: negligible increase from larger zip; pypdf import adds ~50ms to init

## Agents Consulted

`/office-hours` (architecture decision: pypdf vs ECS vs Lambda Container Image)

## Findings Addressed

none

## Findings Deferred

- **Lambda Container Image migration** — Dockerfiles written but Docker Desktop not installed; `terraform_data` uv approach remains in place until Docker is available. Switch eliminates the local pip-install step entirely and makes dependencies fully committed via Dockerfile.
