# ADR 0001 — SSM Parameter Store (SecureString) for API Credentials

**Date:** 2026-05-31
**Status:** Accepted

## Context

P4's Lambda function needs a Gemini API key at runtime. The initial implementation passed it as a Terraform variable (`var.gemini_api_key`) which was injected directly into the Lambda environment as `GEMINI_API_KEY`. This approach has three concrete problems:

1. The key value is stored in Terraform state (plaintext unless state is encrypted).
2. The key is visible in the Lambda configuration tab in the AWS console to anyone with `lambda:GetFunction`.
3. Terraform must know the key value at `plan`/`apply` time, meaning it must exist in `terraform.tfvars` or be passed on the CLI — both of which require the operator to handle it explicitly every run.

The project's `api.txt` (gitignored) is the local source of truth for credentials and the key must never enter the git tree or Terraform state.

## Decision

Store the Gemini API key in **AWS SSM Parameter Store as a SecureString** (KMS-encrypted with the AWS-managed `aws/ssm` key). Lambda fetches it at cold start via `ssm:GetParameter` with `WithDecryption=True` and caches the value in a module-level variable for the container's lifetime.

Terraform's role is narrowed to:
- Provisioning the SSM parameter *resource* with a `"PLACEHOLDER"` value and `lifecycle { ignore_changes = [value] }` so it never overwrites the real key.
- Passing only the parameter *path* (`/cloud-portfolio/gemini-api-key`) to Lambda as an environment variable (`GEMINI_API_KEY_PATH`).

The real key is loaded once via a CLI bootstrap command run by the operator after `terraform apply`:
```bash
aws ssm put-parameter \
  --name "/cloud-portfolio/gemini-api-key" \
  --value "$(cat api.txt)" \
  --type SecureString --overwrite \
  --region ap-northeast-2
```

The `/cloud-portfolio/` namespace is shared, allowing future projects to add credentials without each needing a separate bootstrap process.

## Alternatives Considered

**Plain `terraform.tfvars`** — simple, zero AWS cost, but the key appears in Terraform state and in the Lambda environment tab. Rejected because security level must be high.

**AWS Secrets Manager** — identical runtime-fetch pattern with auto-rotation support. Costs $0.40/secret/month. Rotation is not useful for an API key that is rotated manually anyway. Rejected as unnecessary cost for this use case; preferred if database credentials are added later.

**SSM + Lambda Extension (in-process cache)** — eliminates even the cold-start SSM API call. Adds an extension layer to manage and debug. Rejected as overkill for a single secret on a low-traffic chatbot.

## Consequences

- `var.gemini_api_key` is removed from `variables.tf` — no sensitive value flows through Terraform.
- Lambda IAM role requires `ssm:GetParameter` scoped to the specific parameter ARN.
- Cold start includes one SSM API call (~30–80ms). Warm invocations pay zero overhead (module-level cache).
- Key rotation = re-run the `put-parameter` CLI command. No `terraform apply` needed.
- If the SSM parameter is not bootstrapped before Lambda invocation, `get_parameter` raises a `ParameterNotFound` exception, which the existing `except Exception` handler catches and returns as the fallback chat message. This is visible and diagnosable — not silent.
