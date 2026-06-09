# 26-06-10 [bug] P5 Textract Subscription and Titan V2 Dimensions

**Type:** bug
**Branch / Commit:** Testo / uncommitted

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project5-document-engine/variables.tf` | — | `aws_region` default changed from `ap-northeast-2` to `us-east-1` |
| `project5-document-engine/lambda/ingest/index.py` | `get_embedding()` | `"dimensions": 1536` → `"dimensions": 1024` |
| `project5-document-engine/lambda/query/index.py` | `get_embedding()` | `"dimensions": 1536` → `"dimensions": 1024` |
| `project5-document-engine/outputs.tf` | `step1_create_index` output | `"dimension": 1536` → `"dimension": 1024` in OpenSearch index mapping curl body |

## Why Changed

First live deployment of P5 on 2026-06-09 produced two distinct runtime failures captured in CloudWatch logs and DynamoDB:

**Bug 1 (ERR-003):** Ingest Lambda failed immediately with `SubscriptionRequiredException` when calling `textract:DetectDocumentText`. Textract in `ap-northeast-2` requires a separate service subscription agreement that the account does not have. The stack was configured to deploy to `ap-northeast-2` but Textract requires an explicit regional subscription there. `us-east-1` does not have this restriction.

**Bug 2 (ERR-004):** Query API returned 500 with `ValidationException: Malformed input request: #: only 1 subschema matches out of 2`. The embedding call passed `"dimensions": 1536` to `amazon.titan-embed-text-v2:0`, but Titan V2 only accepts 256, 512, or 1024. The value 1536 is the fixed output of Titan V1 and was incorrectly carried over. The same invalid value was in the OpenSearch index mapping in `outputs.tf`, which would have caused a dimension mismatch between stored and query vectors.

## Contents Diff

**`variables.tf`**
```hcl
# Before
default = "ap-northeast-2"

# After
default = "us-east-1"
```

**`lambda/ingest/index.py` and `lambda/query/index.py` — `get_embedding()`**
```python
# Before
body = json.dumps({
    "inputText":  text[:8000],
    "dimensions": 1536,
    "normalize":  True,
})

# After
body = json.dumps({
    "inputText":  text[:8000],
    "dimensions": 1024,
    "normalize":  True,
})
```

**`outputs.tf` — `step1_create_index`**
```
# Before
"embedding": { "type": "knn_vector", "dimension": 1536, ... }

# After
"embedding": { "type": "knn_vector", "dimension": 1024, ... }
```

## Improvements

- Textract will now succeed in `us-east-1` without requiring a regional service subscription
- Titan V2 embedding calls will no longer fail schema validation — `1024` is the highest valid dimension for V2 and is accepted without error
- OpenSearch index dimension is now consistent with the embedding dimension — no mismatch possible
- Entire P5 stack is now single-region (`us-east-1`) — Bedrock was already calling `us-east-1`; this eliminates the only cross-region call

## Performance Impact

- Region change (`ap-northeast-2` → `us-east-1`): latency from Korea increases slightly for S3/Lambda, but this is a portfolio/test project — not a concern
- Dimension reduction (1536 → 1024): embedding vectors are 33% smaller, which reduces OpenSearch storage and speeds up kNN search; semantic quality impact is negligible for this use case

## Agents Consulted

none — bugs identified from live CloudWatch logs and DynamoDB scan screenshots

## Findings Addressed

- ERR-003: `SubscriptionRequiredException` — fixed via `aws_region` change
- ERR-004: `ValidationException` invalid dimensions — fixed in `lambda/ingest/index.py`, `lambda/query/index.py`, `outputs.tf`

## Findings Deferred

none
