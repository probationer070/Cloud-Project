# P4 Build Plan — Customer-Service AI Chatbot

A customer-service AI chatbot that reuses the building-block patterns of P1–P3. This document is
the full design and build plan for P4; implementation progress is kept in sync with
`project4-ai-chatbot/README.md`.

> Related design docs: [P1](design/p1-static-web/design.md) · [P2](design/p2-serverless-pipeline/design.md) · [P3](design/p3-smart-vault/design.md)

---

## 1. Decision: AI Provider

- Use the **Google Gemini API** (free/paid tier). Chosen over AWS Bedrock.
- The API key is stored in a **Lambda environment variable** (`GEMINI_API_KEY`) and injected from `var.gemini_api_key`.
- For the AI layer only, **no AWS payment card is required**. Everything else integrates with the AWS stack.
- You can switch to Bedrock by setting `ai_provider` in `variables.tf` to `"bedrock"` and running `terraform apply`.

---

## 2. Overall Architecture

```
[Browser / external app · curl]
            │
            ▼
      API Gateway  ──→  Lambda (chatbot core logic)
                          │  1. Fetch conversation history (DynamoDB)
                          │  2. Build prompt
                          │  3. Call Gemini API
                          │  4. Validate/route response
                          │  5. Save conversation history (DynamoDB)
                          │
              ┌───────────┴───────────┐
          DynamoDB                 Gemini API
     (conversation history)   (AI response generation)
              │
              ▼ (on agent-handoff detected)
            SNS → email notification

  Monitoring: CloudWatch (response time / error rate)
  Web UI: S3 + CloudFront (reuses P1)
```

---

## 3. AWS Resources and Roles

| Resource | Role | Free tier |
|--------|------|-----------|
| API Gateway | Web UI + external REST endpoint | 1M requests/mo |
| Lambda | Entire chatbot core logic | 1M requests/mo |
| DynamoDB | Per-session conversation history | 25 GB |
| Gemini API | AI response generation | Free tier (+ pay-as-you-go) |
| S3 | Static web UI hosting | free |
| CloudFront | Web UI CDN | free |
| SNS | Agent-handoff notifications | free |
| CloudWatch | Response time / error rate monitoring | free |

> Estimated cost during development: **about $0** on the Gemini free tier.

---

## 4. Lambda Internal Logic (5 Steps)

### Step 1. Fetch conversation history
- Look up prior messages in DynamoDB by `session_id`.
- If the session does not exist, start a new one.
- If it exists, load only the **last 10 turns** to manage the context window.

### Step 2. Build the prompt
- **System Prompt (fixed):** act as the company's customer-service agent; friendly, professional tone;
  honestly admit when something is unknown; politely decline profane/abusive language;
  guide the user to an agent handoff when an issue cannot be resolved.
- Dynamically prepend the conversation history before the current user message.

### Step 3. Call the Gemini API
- Send the assembled prompt to Gemini and receive the generated response.

### Step 4. Validate and route the response
- Normal response: return as-is.
- Agent request: **send an SNS notification** + return a "connecting you now" message (`escalated: true`).
- Abusive content: replace with a warning message.
- Empty response: return a default fallback message.

### Step 5. Save conversation history
- Save the current turn to DynamoDB with `session_id`, `timestamp`, `role`, and `content` fields.
- Set a **24-hour TTL** — auto-expiry for cost control.

---

## 5. DynamoDB Table Structure

- **Table name:** `p4-chatbot-sessions`
- **Partition key:** `session_id` (String) — unique per browser/user
- **Sort key:** `timestamp` (String) — orders the conversation
- **Additional fields:**
  - `role` — `user` or `assistant`
  - `content` — message text
  - `ttl` — Unix timestamp, auto-deleted after 24 hours

(Billing: `PAY_PER_REQUEST` + TTL auto-expiry — reuses the P2 DynamoDB pattern.)

---

## 6. Web UI

Hosted on P1's existing S3 + CloudFront setup.

- Chat window showing user input + AI responses
- Auto-generated session ID stored in the browser's `localStorage`
- Conversation history display
- Agent-handoff button
- Loading indicator

---

## 7. Links to Previous Projects

- **P1 (S3 + CloudFront):** reused for hosting the chatbot web UI.
- **P2 (DynamoDB pattern):** reused for the conversation-history storage structure (`PAY_PER_REQUEST` + TTL).
- **P3 (SNS pattern):** reused for the agent-handoff email notification.

---

## 8. Deployment and Test Order

1. Provision the infrastructure with `terraform apply`.
2. Upload the web UI to S3 (`aws s3 sync`), then test the chat in a browser.
3. Test the REST endpoint directly with `curl`.
4. Trigger an agent handoff and confirm the SNS email is received.
5. Confirm the conversation history is stored in DynamoDB.
6. Check response time / error rate on the CloudWatch dashboard.

### Validation Checklist
- [ ] Basic conversation response confirmed via curl
- [ ] Prior conversation remembered across consecutive calls with the same `session_id`
- [ ] "Agent handoff" request returns `escalated: true` + email notification received
- [ ] Conversation history stored in DynamoDB (`p4-chatbot-sessions`)
- [ ] Browser web UI chat works
- [ ] CloudWatch dashboard shows invocation count / response time graphs
