# ERR-003 — Textract SubscriptionRequiredException in ap-northeast-2

---

## Summary

The P5 Ingest Lambda failed on every document upload because Textract in `ap-northeast-2` (Seoul) requires an explicit service subscription agreement that the account does not have. The Lambda logged `SubscriptionRequiredException` and DynamoDB recorded `status: failed` with 0 chunks indexed.

---

## Metadata

| Field | Value |
|-------|-------|
| **ID** | ERR-003 |
| **Date Discovered** | 2026-06-09 |
| **Date Resolved** | 2026-06-10 |
| **Severity** | `dev-only` |
| **Component** | `project5-document-engine/lambda/ingest/index.py`, `variables.tf` |
| **Introduced In** | e47c91c (feat: Implement document ingestion and query processing with AWS services) |
| **Discovered By** | `manual-test` — CloudWatch logs from first deployment run |

---

## Symptom

Lambda immediately failed after S3 trigger. CloudWatch logs:

```
[Ingest] 처리 시작: s3://p5-doc-engine-docs-jaehwan-20250608/sample.pdf → doc_id=2a958b1b-...
[Ingest] ❌ 실패: An error occurred (SubscriptionRequiredException) when calling the
DetectDocumentText operation: The AWS Access Key Id needs a subscription for the service
```

DynamoDB record showed `"status": "failed"`, `"chunk_count": 0`, `"char_count": 0` with the full error in the `error` field.

---

## Root Cause

`variables.tf` defaulted `aws_region` to `ap-northeast-2`. Amazon Textract in `ap-northeast-2` requires an AWS service subscription agreement separate from standard account activation. The account had Bedrock working (cross-region to `us-east-1`) but had never subscribed to Textract in Seoul. The Textract client was initialized with `region_name=AWS_REGION` (the Lambda execution region), so it called the Seoul endpoint which rejected the request.

This was masked during development because the AWS Console "Complete your account setup" message was initially interpreted as an account activation issue rather than a region-specific service subscription requirement.

---

## Fix Applied

### Files Changed

| File | Change |
|------|--------|
| `project5-document-engine/variables.tf` | `aws_region` default changed from `"ap-northeast-2"` to `"us-east-1"` |

### Code Change Summary

Moving the entire stack to `us-east-1` where Textract is available without a separate subscription agreement. Bedrock was already calling `us-east-1` cross-region; this makes all services single-region.

```hcl
# Before
variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

# After
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
```

---

## Prevention

### What to Check in Future

- [ ] When adding any new AWS service to a project, verify it is available **without additional subscription** in the target `aws_region` before writing code — check the AWS Regional Services List
- [ ] When `aws_region` is set to a non-US region, explicitly verify each service: Textract, Rekognition, Comprehend, and Translate have patchy regional availability and may require service agreements
- [ ] After `terraform apply`, check CloudWatch logs on the first Lambda invocation before declaring the deployment successful

### Agent / Checklist Update

| Agent File | Change Made | Rationale |
|-----------|-------------|-----------|
| `.agents/security.md` | N/A | Not a security concern |

N/A — the pattern (verify regional service availability before use) is a deployment concern, not a code concern. Add a step to the P5 README deployment checklist to verify each service in the AWS Regional Services List before changing `aws_region`.

### Test Added

No automated test added — this is an infrastructure/account configuration issue, not a testable code path. Prevention is the regional availability check above.

---

## Related

- **Related errors:** None
- **Agent findings:** None
- **CHANGELOG entry:** `docs/changelog/26-06-10 [bug] P5 Textract Subscription and Titan V2 Dimensions.md`
