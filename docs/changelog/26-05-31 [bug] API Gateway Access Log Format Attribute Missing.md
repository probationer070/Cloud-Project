# 26-05-31 [bug] API Gateway Access Log Format Attribute Missing

**Type:** bug
**Branch / Commit:** dev / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project4-ai-chatbot/main.tf` | `aws_apigatewayv2_stage.chatbot` | Added required `format` attribute to `access_log_settings` block |

## Why Changed

`terraform plan` failed with: `Required attribute "format" not specified: An attribute named "format" is required here`. The `aws_apigatewayv2_stage` resource's `access_log_settings` block requires a `format` string specifying the log fields to emit per request. The block was added with only `destination_arn`, omitting `format`.

## Contents Diff

**`main.tf` — `aws_apigatewayv2_stage.chatbot`**
```hcl
# Before
access_log_settings {
  destination_arn = aws_cloudwatch_log_group.api_access.arn
}

# After
access_log_settings {
  destination_arn = aws_cloudwatch_log_group.api_access.arn
  format = jsonencode({
    requestId          = "$context.requestId"
    sourceIp           = "$context.identity.sourceIp"
    requestTime        = "$context.requestTime"
    httpMethod         = "$context.httpMethod"
    routeKey           = "$context.routeKey"
    status             = "$context.status"
    responseLength     = "$context.responseLength"
    integrationLatency = "$context.integrationLatency"
  })
}
```

Fields intentionally omitted from the format: request body and authorization headers — logging those would expose user chat messages and credentials to CloudWatch.

## Improvements

- `terraform plan` no longer errors on this resource
- Access log format captures routing and latency fields without logging sensitive request content

## Performance Impact

none

## Agents Consulted

security

## Findings Addressed

- [BLOCK] `main.tf:143`: missing required `format` attribute in `access_log_settings` — Terraform could not plan

## Findings Deferred

none
