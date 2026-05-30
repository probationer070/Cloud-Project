# 26-05-30 [upgrade] API Gateway REST API with Native Key Auth

**Type:** upgrade
**Branch / Commit:** dev / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `main.tf` | API Gateway section | Replaced 4 `aws_apigatewayv2_*` resources with 10 `aws_api_gateway_*` REST API v1 resources |
| `main.tf` | `aws_lambda_function.restore` env | Removed `RESTORE_API_KEY` environment variable |
| `main.tf` | `aws_lambda_permission.apigw_restore` | Updated `source_arn` to reference `aws_api_gateway_rest_api` |
| `lambda/restore/index.py` | `lambda_handler` | Removed manual API key validation block and `RESTORE_API_KEY` env read |
| `variables.tf` | `restore_api_key` | Removed variable entirely |
| `terraform.tfvars` | `restore_api_key` | Removed empty value |
| `outputs.tf` | `restore_api_endpoint` | Updated to reference `aws_api_gateway_stage` |
| `outputs.tf` | `restore_api_key_value` (new) | Added sensitive output for the AWS-generated API key |
| `outputs.tf` | `test_restore_api` | Added `x-api-key` header to test curl command |

## Why Changed

`terraform.tfvars` had `restore_api_key = ""` — an empty string. The Restore Lambda read this as `RESTORE_API_KEY`, and every request failed with `[Restore] ❌ 인증 실패: 올바르지 않거나 누락된 API Key` (403).

Root cause: HTTP API v2 (`aws_apigatewayv2_api`) does not support native API key management. There was no AWS-managed key — the key had to be set manually by the operator, and it was never set. Migrating to REST API v1 (`aws_api_gateway_rest_api`) gives AWS full ownership of key creation and enforcement. With `api_key_required = true` on the method, API Gateway rejects requests without a valid key before Lambda is ever invoked — no application-level validation needed.

## Contents Diff

**`lambda/restore/index.py`**
```python
# Before
RESTORE_API_KEY = os.environ["RESTORE_API_KEY"]
AWS_REGION    = os.environ.get("AWS_REGION", "ap-northeast-2")

def lambda_handler(event, context):
    headers = event.get("headers", {})
    client_key = headers.get("x-api-key") or headers.get("X-API-Key")
    if not client_key or client_key != RESTORE_API_KEY:
        print("[Restore] ❌ 인증 실패: 올바르지 않거나 누락된 API Key")
        return response(403, {"error": "Forbidden: Invalid API Key"})

# After
AWS_REGION = os.environ.get("AWS_REGION", "ap-northeast-2")

def lambda_handler(event, context):
    # API Gateway REST API가 api_key_required = true로 설정되어
    # 유효한 API Key 없는 요청은 Lambda 호출 전에 Gateway에서 403 반환
```

## Improvements

- API key is created and managed by AWS — no manual value to set or rotate in tfvars
- Invalid/missing key requests are rejected at the gateway; Lambda is never billed for auth failures
- `terraform output -raw restore_api_key_value` provides the key after deploy
- `variables.tf` and `terraform.tfvars` no longer contain a sensitive placeholder

## Performance Impact

REST API v1 has slightly higher latency (~10-30ms) than HTTP API v2 per request. Acceptable for a manual restore operation that runs infrequently.

## Agents Consulted

architecture, security

## Findings Addressed

- [BLOCK] `restore_api_key = ""` caused 403 on every request; root cause was no AWS-managed key in HTTP API v2

## Findings Deferred

none
