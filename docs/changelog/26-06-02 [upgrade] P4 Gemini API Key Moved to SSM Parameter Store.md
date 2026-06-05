# 26-06-02 [upgrade] P4 Gemini API Key Moved to SSM Parameter Store

**Type:** upgrade
**Branch / Commit:** Testo / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project4-ai-chatbot/variables.tf` | `gemini_api_key` variable | Removed entirely |
| `project4-ai-chatbot/main.tf` | `aws_lambda_function.chatbot` env vars | Replaced `GEMINI_API_KEY = var.gemini_api_key` with `GEMINI_API_KEY_PATH = "/cloud-portfolio/gemini-api-key"` |
| `project4-ai-chatbot/iam.tf` | `aws_iam_role_policy.chatbot` | Added `ssm:GetParameter` scoped to `/cloud-portfolio/gemini-api-key` ARN |
| `project4-ai-chatbot/lambda/chatbot/index.py` | `get_gemini_api_key()` (new), `call_gemini()` | Replaced env var read with SSM fetch + container-lifetime cache |

## Why Changed

Two triggers:

1. **Security policy violation** — `variables.tf` had `gemini_api_key` with `default = ""` and a `sensitive = true` marker. Even with `sensitive`, the value is injected into the Lambda environment as plaintext and visible in the AWS Lambda console under Environment Variables. This violates least-exposure principle.

2. **tf-all.ps1 destroy failure** — After removing the empty default, Terraform prompted for the key at runtime. `tf-all.ps1` passes `-input=false` to all terraform commands, so destroy on P4 exited with code 1. The only safe fix without putting the key in a file was to eliminate the variable entirely.

ADR 0001 (`docs/adr/0001-ssm-parameter-store-for-api-credentials.md`) had already decided SSM was the correct approach. This change implements that decision.

## Contents Diff

**`variables.tf` — `gemini_api_key` variable**
```hcl
# Before
variable "gemini_api_key" {
  description = "Google AI Studio API Key (ai_provider=gemini 시 필요)"
  type        = string
  sensitive   = true
}

# After
# (removed entirely)
```

**`main.tf` — Lambda env vars**
```hcl
# Before
GEMINI_API_KEY   = var.gemini_api_key

# After
GEMINI_API_KEY_PATH = "/cloud-portfolio/gemini-api-key"
```

**`iam.tf` — SSM permission**
```hcl
# After (new statement added)
{
  Effect   = "Allow"
  Action   = ["ssm:GetParameter"]
  Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/cloud-portfolio/gemini-api-key"
}
```

**`index.py` — `get_gemini_api_key()` + `call_gemini()`**
```python
# Before
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

def call_gemini(user_message, history):
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY 환경변수가 설정되지 않았습니다")
    ...
    "x-goog-api-key": GEMINI_API_KEY,

# After
GEMINI_API_KEY_PATH = os.environ.get("GEMINI_API_KEY_PATH", "/cloud-portfolio/gemini-api-key")
ssm = boto3.client("ssm")
_gemini_api_key = None

def get_gemini_api_key() -> str:
    global _gemini_api_key
    if _gemini_api_key is None:
        resp = ssm.get_parameter(Name=GEMINI_API_KEY_PATH, WithDecryption=True)
        _gemini_api_key = resp["Parameter"]["Value"]
    return _gemini_api_key

def call_gemini(user_message, history):
    api_key = get_gemini_api_key()
    ...
    "x-goog-api-key": api_key,
```

## Improvements

- Gemini API key no longer appears in Terraform state, Lambda console, or source code
- `tf-all.ps1 destroy` no longer fails on P4 — the prompting variable is gone
- SSM fetch is cached for the Lambda container lifetime — no repeated SSM calls per request
- IAM permission is scoped to exact parameter path, not `ssm:*` or `parameter/*`

## Performance Impact

- Cold start: +1 SSM API call (~10–30ms) on first invocation per container
- Warm invocations: zero overhead (cached in `_gemini_api_key`)

## Agents Consulted

security

## Findings Addressed

- [BLOCK] Plaintext API key injectable via Terraform variable into Lambda env vars — fixed by SSM migration
- [WARN] Empty default on sensitive variable allows silent deployment with no key — fixed by removing variable

## Findings Deferred

none
