# Plan: P5 Container Lambda ECR Switch

**Opened:** 26-06-10
**Closed:** —
**Active Project:** P5 — Intelligent Document Analysis Engine (RAG)

---

## Context

P5 currently deploys both Lambda functions as zip packages via `archive_file` +
local `uv pip install`. Dockerfiles already exist in `lambda/ingest/` and
`lambda/query/` and use the correct `public.ecr.aws/lambda/python:3.12` base image,
but Terraform ignores them entirely.

The goal is to switch to container image deployment (ECR + `package_type = "Image"`)
so the portfolio demonstrates real Docker + ECR usage — not just placeholder files.
Design decisions were recorded via `/office-hours` on 26-06-10.

Full design doc: `~/.gstack/projects/cloud-project/eajwa-Testo-design-20260610-071534.md`

---

## Goals

1. **Switch both Lambdas to container image deployment** — verify: `terraform apply`
   completes, `aws ecr list-images` shows images in both repos, both Lambda functions
   show `PackageType: Image` in AWS Console.

2. **Validate the full P5 pipeline still works** — verify: CloudWatch logs show
   `[Ingest] ✅ 완료: N개 청크 색인` after PDF upload; query API returns
   `{"answer": "...", "sources": [...]}`.

3. **Write changelog entry** — verify: entry exists in `docs/changelog/` covering
   the container switch (files changed, why, before/after diff).

4. **Run `terraform destroy` immediately after testing** — verify: OpenSearch domain
   `p5-doc-engine-search` is gone from AWS Console.

---

## Known Blockers

- [ ] **Docker Desktop must be installed and running** before `terraform apply` —
      Terraform calls `docker build` and `docker push` via `local-exec`
- [ ] **Bedrock model access** for `amazon.titan-embed-text-v2:0` and
      `anthropic.claude-3-5-haiku-20241022-v1:0` in `us-east-1` (same as before)
- [ ] **AWS CLI credentials** have ECR permissions (admin user: yes, but verify
      `aws ecr describe-repositories` works before running apply)
- [ ] Cost budget: OpenSearch ~$0.86/day — destroy immediately after testing

---

## Files to Read First

- `project5-document-engine/main.tf` — the file being changed; know what you're removing
- `project5-document-engine/lambda/ingest/Dockerfile` — already correct, no changes needed
- `project5-document-engine/lambda/query/Dockerfile` — already correct, no changes needed
- `project5-document-engine/README.md` — validation checklist (Steps 4–7 still apply after the switch)
- `docs/plan/26-06-08 P5 Document Engine.md` — prior plan with full PowerShell deployment sequence

---

## main.tf Changes (exact)

### Remove these blocks entirely

```hcl
resource "terraform_data" "install_ingest_deps" { ... }
data "archive_file" "ingest" { ... }
data "archive_file" "query" { ... }
```

### Add — ECR repositories (after the SNS section, before Lambda)

```hcl
resource "aws_ecr_repository" "ingest" {
  name                 = "${var.project_name}-ingest"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = var.common_tags
}

resource "aws_ecr_repository" "query" {
  name                 = "${var.project_name}-query"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = var.common_tags
}
```

### Add — docker build + push (replace the removed terraform_data block)

```hcl
resource "terraform_data" "build_push_ingest" {
  triggers_replace = [
    filemd5("${path.module}/lambda/ingest/Dockerfile"),
    filemd5("${path.module}/lambda/ingest/index.py"),
    filemd5("${path.module}/lambda/ingest/requirements.txt"),
  ]
  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.ingest.repository_url}; docker build -t ${aws_ecr_repository.ingest.repository_url}:latest ${path.module}/lambda/ingest; docker push ${aws_ecr_repository.ingest.repository_url}:latest"
  }
  depends_on = [aws_ecr_repository.ingest]
}

resource "terraform_data" "build_push_query" {
  triggers_replace = [
    filemd5("${path.module}/lambda/query/Dockerfile"),
    filemd5("${path.module}/lambda/query/index.py"),
  ]
  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.query.repository_url}; docker build -t ${aws_ecr_repository.query.repository_url}:latest ${path.module}/lambda/query; docker push ${aws_ecr_repository.query.repository_url}:latest"
  }
  depends_on = [aws_ecr_repository.query]
}
```

> `interpreter = ["PowerShell", "-Command"]` is required — the ECR login pipe (`|`)
> behaves inconsistently under Terraform's default `cmd.exe` on Windows.
> PowerShell `;` replaces `&&` since `&&` is not supported in PowerShell 5.1.

### Change — aws_lambda_function.ingest

Remove: `handler`, `runtime`, `filename`, `source_code_hash`

Add:
```hcl
package_type = "Image"
image_uri    = "${aws_ecr_repository.ingest.repository_url}:latest"
depends_on   = [terraform_data.build_push_ingest]

lifecycle {
  replace_triggered_by = [terraform_data.build_push_ingest]
  # Required: without this, code changes push a new :latest to ECR
  # but Lambda silently keeps running the previous image.
}
```

### Change — aws_lambda_function.query

Same pattern as ingest:

Remove: `handler`, `runtime`, `filename`, `source_code_hash`

Add:
```hcl
package_type = "Image"
image_uri    = "${aws_ecr_repository.query.repository_url}:latest"
depends_on   = [terraform_data.build_push_query]

lifecycle {
  replace_triggered_by = [terraform_data.build_push_query]
}
```

---

## Deploy Sequence (PowerShell)

Run from `project5-document-engine\`:

```powershell
# 0. Verify Docker Desktop is running
docker info

# 1. Deploy (builds images, pushes to ECR, deploys container Lambdas)
terraform init   # re-init needed — new ECR resources
terraform apply

# 2. Verify ECR images exist
aws ecr list-images --repository-name p5-doc-engine-ingest --region us-east-1
aws ecr list-images --repository-name p5-doc-engine-query  --region us-east-1

# 3. Create OpenSearch index (same as before — dimension 1024)
$ENDPOINT = terraform output -raw opensearch_endpoint
$KEY      = aws configure get aws_access_key_id
$SECRET   = aws configure get aws_secret_access_key
curl.exe -X PUT "$ENDPOINT/documents" `
  --aws-sigv4 "aws:amz:us-east-1:es" `
  --user "${KEY}:${SECRET}" `
  -H "Content-Type: application/json" `
  -d '{\"settings\":{\"index\":{\"knn\":true}},\"mappings\":{\"properties\":{\"embedding\":{\"type\":\"knn_vector\",\"dimension\":1024,\"method\":{\"name\":\"hnsw\",\"space_type\":\"cosinesimil\",\"engine\":\"nmslib\"}}}}}'

# 4. Upload PDF and watch logs
$BUCKET = terraform output -raw documents_bucket
aws s3 cp sample_docs\sample.pdf s3://$BUCKET/sample.pdf
aws logs tail /aws/lambda/p5-doc-engine-ingest --follow --region us-east-1

# 5. Query API
$API = terraform output -raw query_api_endpoint
curl.exe -X POST $API -H "Content-Type: application/json" `
  -d '{\"question\": \"What was the Q4 revenue?\"}'

# 6. Destroy
aws s3 rm s3://$BUCKET --recursive
terraform destroy
```

---

## Out of Scope

- **Approach C (GitHub Actions CI/CD)** — add ECR push step to `.github/workflows/terraform-ci.yml`
  and ECR permissions to `bootstrap/main.tf`; planned as a follow-up after this is verified.
- Image tag pinning (git SHA instead of `latest`) — natural upgrade when CI/CD is added.
- API key auth on the query endpoint.
- P5 design doc (`docs/design/p5-document-engine/design.md`) — still outstanding from prior plan.
- P5 remote state backend (`backend.tf`) — still outstanding from prior plan.
