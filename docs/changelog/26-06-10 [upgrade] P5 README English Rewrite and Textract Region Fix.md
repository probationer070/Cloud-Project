# 26-06-10 [upgrade] P5 README English Rewrite and Textract Region Fix

**Type:** upgrade
**Branch / Commit:** Testo / uncommitted

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project5-document-engine/README.md` | — (doc) | Full rewrite: Korean → English; added Prerequisites section with AWS account activation warning; corrected expected CloudWatch log output; added Windows/PowerShell variants for every command; rewrote Common Errors section |
| `project5-document-engine/lambda/ingest/index.py` | module-level client init | Added `region_name=AWS_REGION` to `boto3.client("textract")` |

## Why Changed

User hit the AWS Console "Complete your account setup" wall when navigating to Textract. Diagnosis via /office-hours session revealed the account was in fact activated (Bedrock was accessible), and the real issue was the console showing a stale/region-mismatched page. During diagnosis, two separate issues were also found in the README:

1. The expected CloudWatch log output described an async Textract job (`[INFO] Textract job started: xxxxxxxx`) but the code uses the synchronous `detect_document_text` API — no job ID is ever produced. This would cause users to wait for a log message that never appears.
2. The README was entirely in Korean with no Windows/PowerShell command variants, making it hard to follow on a Windows development environment.

The Textract client was also initialized without `region_name`, relying on boto3's implicit detection from the Lambda execution environment. While this works, it is inconsistent with the Bedrock client (which already uses `region_name=BEDROCK_REGION`) and can be confusing during local testing.

## Contents Diff

**`project5-document-engine/lambda/ingest/index.py` — module-level client init**
```python
# Before
textract = boto3.client("textract")
bedrock  = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)

# After
textract = boto3.client("textract", region_name=AWS_REGION)
bedrock  = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)
```

**`project5-document-engine/README.md` — expected log output section**
```
# Before (incorrect — described async job ID that code never produces)
[INFO] Textract job started: xxxxxxxx
[INFO] Extracted N chunks
[INFO] Indexed N vectors to OpenSearch
[INFO] Status updated to completed

# After (matches actual Lambda print() calls)
[Ingest] 처리 시작: s3://[bucket]/sample.pdf → doc_id=xxxxxxxx
[Ingest] 텍스트 추출 완료: NNN자
[Ingest] 청크 분할 완료: N개
[Ingest] ✅ 완료: N개 청크 색인
```

**`project5-document-engine/README.md` — Common Errors: Textract entry**
```
# Before
**Textract is not visible in the AWS Console or returns `InvalidAction`**
→ You are looking at the wrong region. Textract is only available in select regions — us-east-1 is the safest choice.
→ Do not change aws_region to ap-northeast-2 (Seoul) — Textract is not supported there.  ← WRONG

# After
**Textract console shows "Complete your account setup" or blocks access**
→ Your AWS account is not fully activated. This blocks ALL premium services (Textract, Bedrock, OpenSearch), not just Textract.
→ Go to AWS Console → Account and complete: (1) credit card verified with $1 hold, (2) identity verification, (3) support plan selected (Basic = free).
→ AWS can take up to 24 hours to fully activate after all steps are complete.
→ Unlike Bedrock, Textract does NOT require activation via the console once your account is active.
```

## Improvements

- README is now fully English with side-by-side Windows/PowerShell and Linux/macOS commands for every deployment step — usable on the actual dev environment (Windows 11)
- Prerequisites section added at the top: AWS account activation requirement is now the first thing a reader sees, not buried in Common Errors
- Expected log output in README now matches real Lambda output — users can verify Textract worked without confusion about missing job IDs
- Textract client uses explicit `region_name`, consistent with the Bedrock client pattern in the same file
- Common Errors section now covers the real Textract blocker (account setup wall) with actionable steps

## Performance Impact

- Lambda: no runtime performance change; `region_name` is resolved at import time and was already resolving to the same value via Lambda's `AWS_REGION` env var
- README: +176 lines (Korean doc was terse; English version adds per-OS command blocks and a full cost table)

## Agents Consulted

`/office-hours`

## Findings Addressed

- README/code mismatch on Textract log output — fixed (log output now matches `detect_document_text` sync API)
- Implicit Textract region reliance — fixed (`region_name=AWS_REGION` now explicit)
- README contained incorrect claim that Textract is unavailable in `ap-northeast-2` — corrected and `variables.tf` `aws_region` default reverted to `ap-northeast-2`

## Findings Deferred

none
