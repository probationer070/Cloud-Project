# 26-05-31 [upgrade] P4 Chatbot Security and Latency Hardening

**Type:** upgrade
**Branch / Commit:** dev / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project4-ai-chatbot/lambda/chatbot/index.py` | `call_gemini` | Moved `GEMINI_API_KEY` from URL query param to `x-goog-api-key` header; reduced urllib timeout 30s→25s |
| `project4-ai-chatbot/lambda/chatbot/index.py` | `call_bedrock` | Replaced module-level `bedrock` client with lazy `_get_bedrock()` to skip initialization on Gemini cold starts |
| `project4-ai-chatbot/lambda/chatbot/index.py` | `lambda_handler` (log line) | Removed user message content from CloudWatch log; now logs only session, provider, message length |
| `project4-ai-chatbot/lambda/chatbot/index.py` | `lambda_handler` (response) | Removed `provider` field from response body |
| `project4-ai-chatbot/lambda/chatbot/index.py` | `cors_response` | CORS `Allow-Origin` now reads `ALLOWED_ORIGIN` env var instead of hardcoding `*` |
| `project4-ai-chatbot/main.tf` | `aws_lambda_function.chatbot` | Lambda timeout 30s→45s; added `architectures = ["arm64"]`; added `ALLOWED_ORIGIN` env var |
| `project4-ai-chatbot/iam.tf` | `aws_iam_role_policy.chatbot` | Scoped CloudWatch logs `Resource` from `arn:aws:logs:*:*:*` to this function's specific log groups |
| `project3-smart-vault/iam.tf` | `locals.log_policy` | Same CloudWatch logs scope fix — now references the three P3 Lambda log groups by name |

## Why Changed

Security review of all `.tf` files and Lambda code found two BLOCK-level issues and several WARN-level issues:

1. `GEMINI_API_KEY` was appended as a URL query parameter (`?key=...`), causing it to appear in CloudWatch access logs, `urllib` error tracebacks, and any HTTP proxy logs.
2. Lambda timeout (30s) equalled the Gemini HTTP timeout (30s), meaning a slow Gemini response would cause the Lambda to expire before `save_history` ran — losing the conversation turn with no error to the caller, just a gateway 504.

## Contents Diff

**`index.py` — `call_gemini` (key exposure + timeout fix)**
```python
# Before
url = f".../{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
with urllib.request.urlopen(req, timeout=30) as resp:

# After
url = f".../{GEMINI_MODEL}:generateContent"
req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY}, method="POST")
with urllib.request.urlopen(req, timeout=25) as resp:
```

**`index.py` — Bedrock lazy init**
```python
# Before
bedrock = boto3.client("bedrock-runtime", ...)  # always runs at module load

# After
_bedrock = None
def _get_bedrock():
    global _bedrock
    if _bedrock is None:
        _bedrock = boto3.client("bedrock-runtime", ...)
    return _bedrock
```

**`index.py` — log line**
```python
# Before
print(f"[Chatbot] session={session_id} provider={AI_PROVIDER} msg={user_message[:50]}")

# After
print(f"[Chatbot] session={session_id} provider={AI_PROVIDER} len={len(user_message)}")
```

**`index.py` — CORS origin**
```python
# Before
"Access-Control-Allow-Origin": "*"

# After
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "*")
...
"Access-Control-Allow-Origin": ALLOWED_ORIGIN
```

**`main.tf` — Lambda resource**
```hcl
# Before
timeout       = 30
# (no architectures)

# After
timeout       = 45
architectures = ["arm64"]
ALLOWED_ORIGIN = "https://${aws_cloudfront_distribution.ui.domain_name}"
```

**`iam.tf` — CloudWatch logs scope (P4)**
```hcl
# Before
Resource = "arn:aws:logs:*:*:*"

# After
Resource = [
  "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-chatbot",
  "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-chatbot:*",
  "arn:aws:logs:${var.aws_region}:*:log-group:/aws/apigateway/${var.project_name}",
  "arn:aws:logs:${var.aws_region}:*:log-group:/aws/apigateway/${var.project_name}:*",
]
```

## Improvements

- API key no longer appears in CloudWatch access logs or error tracebacks
- Conversation turns are no longer lost on slow Gemini responses (Lambda outlives the HTTP call by 20s)
- Gemini cold starts no longer pay for a Bedrock DNS/credential handshake
- CORS origin is locked to the deployed CloudFront domain on `terraform apply`; `*` is only the fallback for local dev
- User message content no longer reaches CloudWatch log storage
- IAM log permissions scoped to the actual log groups (P4 + P3)
- ARM64 (Graviton2) matches the pattern already in use by P3; ~20% cheaper per invocation

## Performance Impact

- Cold start latency reduced: Bedrock client init (~50–150ms DNS + credential fetch) skipped when `AI_PROVIDER=gemini`
- Lambda timeout headroom increased: 15s added buffer (30s→45s total, 25s inner timeout) eliminates 504 on slow Gemini responses
- ARM64: ~20% lower Lambda cost; equivalent or better throughput for Python I/O-bound workloads

## Agents Consulted

security, refactoring

## Findings Addressed

- [BLOCK] `index.py:148`: `GEMINI_API_KEY` in URL query param — key leaked in CloudWatch access logs
- [BLOCK] `main.tf:87` + `index.py:156`: Lambda timeout ≤ Gemini timeout — `save_history` never ran on slow calls
- [WARN] `index.py:276`: CORS `Allow-Origin: *` hardcoded in Lambda response
- [WARN] `index.py:80`: User message content (first 50 chars) logged to CloudWatch
- [WARN] `p4/iam.tf:34`, `p3/iam.tf:19`: CloudWatch logs IAM scoped to `arn:aws:logs:*:*:*`
- [WARN] `index.py:31`: Bedrock client eagerly initialized on every cold start
- [WARN] `main.tf:79`: x86_64 instead of ARM64

## Findings Deferred

- [WARN] `main.tf:163`: `POST /chat` has no authentication (`authorization_type = NONE`) — acceptable for learning/test; add API key or JWT before any public deployment
