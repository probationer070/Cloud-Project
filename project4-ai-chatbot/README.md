# Project 4: AI Customer Service Chatbot

> **Standalone project** — P1, P2, and P3 do NOT need to be deployed. P4 creates all its own AWS resources independently.

## Architecture

```
[Web UI]                 [REST API]
 Browser                  curl / external app
    │                          │
    └──────────┬───────────────┘
               ▼
        API Gateway (HTTP v2)
               ▼
        Lambda (chatbot logic)
        ┌──────────────────────────────────────┐
        │ 1. Fetch conversation history        │
        │    (DynamoDB, last 10 turns)         │
        │ 2. Build prompt                      │
        │    (System Prompt + history)         │
        │ 3. Call AI (Gemini / Bedrock)        │
        │    Gemini key: SSM Parameter Store   │
        │    (fetched once at cold start)      │
        │ 4. Route response                    │
        │    (normal / escalate / profanity)   │
        │ 5. Save history (DynamoDB, TTL 24h)  │
        └──────────────────────────────────────┘
             │              │
        DynamoDB         Gemini API
        (history)        or Bedrock
             │
             ▼ (on escalation)
           SNS → email alert

Web UI: S3 (private) ─ OAC ─▶ CloudFront (HTTPS)
```

---

## Deployment Steps

### Step 1. Get a Gemini API Key

```
https://aistudio.google.com/apikey
  → Click "Create API Key"
  → Copy the key (starts with AIzaSy...)
```

### Step 2. Store the Gemini API Key in SSM Parameter Store

```powershell
aws ssm put-parameter `
  --name "/cloud-portfolio/gemini-api-key" `
  --value "AIzaSy..." `
  --type SecureString `
  --region ap-northeast-2
```

> Add `--overwrite` if the parameter already exists.
> Lambda fetches this key once at cold start and caches it for the container lifetime.

### Step 3. Edit variables.tf

```hcl
suffix       = "yourname-20260527"   # ← unique suffix for S3 bucket name (required)
alert_email  = "your@email.com"      # ← email for escalation alerts (required)
company_name = "My Shop"             # ← name shown in chatbot responses (optional)
```

> `gemini_api_key` is NOT in variables.tf — the key lives in SSM (Step 2).

### Step 4. Deploy Infrastructure

```powershell
cd project4-ai-chatbot
terraform init
terraform plan
terraform apply
```

After `terraform apply` completes, note the outputs:

```
chat_api_endpoint          = "https://xxxxx.execute-api.ap-northeast-2.amazonaws.com/v1/chat"
chatbot_ui_url             = "https://d1234abcd.cloudfront.net"
ui_upload_command          = "aws s3 sync ./website/ s3://p4-chatbot-ui-.../ --delete"
cache_invalidation_command = "aws cloudfront create-invalidation ..."
```

### Step 5. Set the API Endpoint in the Web UI

Open `website/index.html` and update this line:

```javascript
const API_ENDPOINT = "https://xxxxx.execute-api.ap-northeast-2.amazonaws.com/v1/chat";
//                    ↑ Replace with the chat_api_endpoint value from Step 4
```

### Step 6. Upload the Web UI to S3

```powershell
# Run the ui_upload_command from Step 4
aws s3 sync ./website/ s3://[bucket-name]/ --delete

# Run the cache_invalidation_command from Step 4
aws cloudfront create-invalidation --distribution-id [dist-id] --paths "/*"
```

### Step 7. Open in Browser

```
Open the chatbot_ui_url from Step 4
e.g. https://d1234abcd.cloudfront.net
```

---

## Test Scenarios

> Run `terraform output` to see the test commands pre-filled with your actual endpoint.
>
> **Model:** Gemma 4 26B (`gemma-4-26b-a4b-it`) via Gemini API — free tier limit: 1,500 requests/day.

### 1. Basic Conversation

```powershell
Invoke-RestMethod `
  -Uri "https://gt7zb6obp8.execute-api.ap-northeast-2.amazonaws.com/v1/chat" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"message": "How do I process a return?", "session_id": "test-001"}'
```

Expected response:
```json
{"response": "To process a return...", "session_id": "test-001", "escalated": false}
```

### 2. Conversation History Continuity

This test also verifies the repeated-response bug is fixed: the second reply must
reference "12345" from the first message. If it gives a generic response instead,
history is broken.

```powershell
# First message
Invoke-RestMethod `
  -Uri "https://gt7zb6obp8.execute-api.ap-northeast-2.amazonaws.com/v1/chat" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"message": "My order number is 12345.", "session_id": "test-003"}'

# Second message — response MUST mention "12345" (proves history is retained)
Invoke-RestMethod `
  -Uri "https://gt7zb6obp8.execute-api.ap-northeast-2.amazonaws.com/v1/chat" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"message": "What was my order number?", "session_id": "test-003"}'
```

Expected: second response contains "12345". Conversation history is working correctly.

### 3. Escalation Trigger

```powershell
Invoke-RestMethod `
  -Uri "https://gt7zb6obp8.execute-api.ap-northeast-2.amazonaws.com/v1/chat" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"message": "Please connect me with a human agent.", "session_id": "test-002"}'
```

Expected response:
```json
{"response": "... You have requested to speak with an agent...", "escalated": true}
```

Check that an alert email arrives at `alert_email`.

### 4. Verify DynamoDB History

```powershell
# Run the check_session_history output command
aws dynamodb query `
  --table-name p4-chatbot-sessions `
  --key-condition-expression "session_id = :sid" `
  --expression-attribute-values '{\":sid\":{\"S\":\"test-003\"}}' `
  --region ap-northeast-2
```

---

## Validation Checklist

- [ ] `terraform output` shows `chat_api_endpoint` and `chatbot_ui_url`
- [ ] SNS subscription confirmation email received → click "Confirm subscription"
- [ ] Basic conversation returns a response (`escalated: false`)
- [ ] Same `session_id` across two calls — second response references first message
- [ ] "Connect me with an agent" → `escalated: true` + email alert received
- [ ] DynamoDB shows conversation history (`check_session_history`)
- [ ] Browser → CloudFront URL → web UI chat works
- [ ] CloudWatch dashboard (`dashboard_url`) shows invocation and latency graphs

---

## Switch to Bedrock (Optional)

```hcl
# variables.tf
ai_provider = "bedrock"

# re-run
terraform apply
```

Cost: ~$1–3/mo at test scale. Seoul region does not support Claude — `bedrock_region` defaults to `us-east-1`.

---

## Destroy Resources

```powershell
# 1. Empty the S3 bucket
aws s3 rm s3://[ui-bucket] --recursive

# 2. Destroy Terraform resources
terraform destroy
```

> The SSM parameter is not managed by Terraform. Delete it manually if no longer needed:
> AWS Console → Systems Manager → Parameter Store → `/cloud-portfolio/gemini-api-key` → Delete
