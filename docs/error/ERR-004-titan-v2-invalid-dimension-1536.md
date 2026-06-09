# ERR-004 — Titan Embeddings V2 Invalid Dimension 1536

---

## Summary

Both P5 Lambda functions requested 1536-dimensional embeddings from `amazon.titan-embed-text-v2:0`, which only supports 256, 512, or 1024 dimensions. Every call to `invoke_model` for embeddings failed with `ValidationException`, causing the ingest pipeline to produce no vectors and the query API to return a 500 error on every request.

---

## Metadata

| Field | Value |
|-------|-------|
| **ID** | ERR-004 |
| **Date Discovered** | 2026-06-09 |
| **Date Resolved** | 2026-06-10 |
| **Severity** | `dev-only` |
| **Component** | `project5-document-engine/lambda/ingest/index.py`, `lambda/query/index.py`, `outputs.tf` |
| **Introduced In** | e47c91c (feat: Implement document ingestion and query processing with AWS services) |
| **Discovered By** | `manual-test` — query API returned 500 on first test run |

---

## Symptom

Query API returned HTTP 500 with:

```
{
  "error": "처리 중 오류가 발생했습니다: An error occurred (ValidationException) when calling
  the InvokeModel operation: Malformed input request: #: only 1 subschema matches out of 2,
  please reformat your input and try again."
}
```

The error surfaced in the query Lambda but the same bug existed in the ingest Lambda — ingest had already failed due to ERR-003 (Textract subscription), so the embedding code path was never reached during ingest testing.

---

## Root Cause

The code used `"dimensions": 1536` for `amazon.titan-embed-text-v2:0`. The value 1536 is the **fixed output size of Titan Embeddings V1** (`amazon.titan-embed-text-v1:0`), which does not accept a `dimensions` parameter at all. Titan Embeddings **V2** added a configurable `dimensions` field but its valid values are **256, 512, and 1024 only**. Passing 1536 fails schema validation ("only 1 subschema matches out of 2" — the `inputText` field matched but the `dimensions` value did not).

The same incorrect value was used in the OpenSearch index mapping (`"dimension": 1536`), which would have caused a mismatch between stored vector size and query vector size if the Lambda had succeeded.

---

## Fix Applied

### Files Changed

| File | Change |
|------|--------|
| `project5-document-engine/lambda/ingest/index.py` | `"dimensions": 1536` → `"dimensions": 1024` in `get_embedding()` |
| `project5-document-engine/lambda/query/index.py` | `"dimensions": 1536` → `"dimensions": 1024` in `get_embedding()` |
| `project5-document-engine/outputs.tf` | `"dimension": 1536` → `"dimension": 1024` in `step1_create_index` curl body |

### Code Change Summary

Changed all three occurrences of 1536 to 1024. The OpenSearch index mapping and both Lambda embedding calls now consistently use 1024 dimensions — the highest value supported by Titan V2.

```python
# Before (both lambda/ingest/index.py and lambda/query/index.py)
body = json.dumps({
    "inputText":  text[:8000],
    "dimensions": 1536,   # ← invalid for Titan V2
    "normalize":  True,
})

# After
body = json.dumps({
    "inputText":  text[:8000],
    "dimensions": 1024,   # ← valid for Titan V2 (max supported value)
    "normalize":  True,
})
```

```hcl
# Before (outputs.tf step1_create_index)
"embedding": { "type": "knn_vector", "dimension": 1536, ... }

# After
"embedding": { "type": "knn_vector", "dimension": 1024, ... }
```

---

## Prevention

### What to Check in Future

- [ ] When using `amazon.titan-embed-text-v2:0`, valid `dimensions` values are **256, 512, 1024** — never 1536
- [ ] When using `amazon.titan-embed-text-v1:0`, do NOT pass a `dimensions` field — V1 always outputs 1536 and ignores or rejects the parameter
- [ ] The OpenSearch index `"dimension"` value in the mapping **must match** the `"dimensions"` value passed to the embedding model — verify these are in sync whenever changing models
- [ ] After changing embedding dimensions, always destroy and recreate the OpenSearch index — it cannot be updated in place

### Agent / Checklist Update

N/A — existing checklist does not cover Bedrock model-specific schema constraints. This is a model API documentation gap, not a code architecture gap.

### Test Added

No automated test added — calling Bedrock is integration-only. Prevention is the cross-check above (Lambda `dimensions` value must match `outputs.tf` index mapping value).

---

## Related

- **Related errors:** ERR-003 (same test run; Textract failure masked this bug in the ingest path)
- **Agent findings:** None
- **CHANGELOG entry:** `docs/changelog/26-06-10 [bug] P5 Textract Subscription and Titan V2 Dimensions.md`
