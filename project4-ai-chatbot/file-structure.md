# P4 File Structure — AI Chatbot

```
project4-ai-chatbot/
│
├── main.tf               # DynamoDB (sessions), SNS (alerts),
│                         #   Lambda (chatbot), CloudWatch log groups,
│                         #   API Gateway HTTP v2 (POST /chat),
│                         #   S3 + CloudFront (web UI),
│                         #   CloudWatch alarms + dashboard
│                         #   aws_ssm_parameter (gemini key placeholder)
│
├── iam.tf                # chatbot-role:
│                         #   logs (scoped to log group ARNs),
│                         #   dynamodb (PutItem/GetItem/Query/BatchWriteItem),
│                         #   sns:Publish, bedrock:InvokeModel,
│                         #   ssm:GetParameter (gemini key)
│
├── variables.tf          # aws_region, project_name, suffix,
│                         #   alert_email, company_name,
│                         #   ai_provider (gemini|bedrock),
│                         #   gemini_model, bedrock_model_id,
│                         #   bedrock_region, common_tags
│                         #   NOTE: gemini_api_key removed — key lives
│                         #   in SSM Parameter Store (/cloud-portfolio/gemini-api-key)
│
├── outputs.tf            # chat_api_endpoint, chatbot_ui_url,
│                         #   ui_upload_command, check_session_history
│
├── lambda/
│   └── chatbot/
│       └── index.py      # 5-step handler:
│                         #   1. get_history (DynamoDB query, last 10 turns)
│                         #   2. call_gemini / call_bedrock
│                         #   3. escalation / profanity routing
│                         #   4. save_history (batch_writer)
│                         #   5. notify_escalation (SNS)
│                         #   Gemini key: lazy SSM fetch via _get_gemini_key()
│                         #   Bedrock client: lazy init via _get_bedrock()
│
├── website/
│   └── index.html        # Chatbot web UI; deployed to S3 + CloudFront
│
└── README.md             # Deploy steps, test scenarios, validation checklist
```

## Key relationships

- Gemini API key is **not** in env vars — fetched from SSM at cold start via `_get_gemini_key()`, cached for container lifetime.
- `AI_PROVIDER` env var switches between Gemini and Bedrock with no code change.
- `ALLOWED_ORIGIN` env var is set by Terraform to `https://<cloudfront-domain>` — Lambda uses it in the CORS response header (not hardcoded `*`).
- CloudFront distribution must exist before Terraform can set `ALLOWED_ORIGIN`. The `aws_lambda_function` resource depends on `aws_cloudfront_distribution.ui` implicitly via the env var reference.
- Lambda timeout (45s) exceeds Gemini HTTP timeout (25s) by 20s — ensures `save_history` always runs even on slow AI responses.

## Bootstrap (one-time, after terraform apply)

```bash
aws ssm put-parameter \
  --name "/cloud-portfolio/gemini-api-key" \
  --value "$(cat api.txt)" \
  --type SecureString --overwrite \
  --region ap-northeast-2
```

## Design reference

[Full P4 build plan](../docs/todo.md) · [ADR: SSM credential storage](../docs/adr/0001-ssm-parameter-store-for-api-credentials.md)
