# Portfolio Role Analysis — Cloud-Project

**Date:** 2026-06-02
**Target:** Mid-level Cloud/DevOps Engineer
**Purpose:** Understand each project's role, map skill coverage, identify gaps, and prepare interview talking points.

---

## Section 1 — The Portfolio Narrative

These four projects are not random. They form a deliberate learning arc:

| Step | Project | What it adds |
|------|---------|--------------|
| 1 | P1 — Static Web | Foundation: hosting, CDN, edge security, IaC |
| 2 | P2 — Serverless Pipeline | Event-driven: multi-service orchestration, async processing |
| 3 | P3 — Smart Vault | Operations: scheduling, backup automation, cross-region DR |
| 4 | P4 — AI Chatbot | Integration: combines P1+P2+P3 patterns into a real product |

The arc shows progression from "I can deploy infrastructure" → "I can design and operate systems." P4 is the flagship because it reuses patterns from all three prior projects — it demonstrates that the earlier work was building toward something, not just isolated exercises.

---

## Section 2 — Each Project's Role

### P1 — Static Web (Security + Performance Hosting)

**One-sentence pitch:** Demonstrates production-grade static hosting where the S3 bucket is never public — traffic only reaches it through a WAF-protected CloudFront distribution.

**Key AWS services:** S3 (private, versioned, AES256), CloudFront (OAC origin), WAF (us-east-1), CloudWatch + SNS

**What interviewers see:**
- You know **OAC** (Origin Access Control) — not the deprecated OAI. This is an active AWS best-practice distinction.
- You deployed **WAF with managed rule groups** (SQLi, XSS, IP reputation, rate limiting) — not just theoretical security.
- You wired **CloudWatch alarms to SNS** for 4xx, 5xx, and WAF block rates — you thought about operations, not just deployment.
- WAF must live in `us-east-1` for CloudFront — you handled multi-region Terraform correctly.

**Why it's non-trivial:** Most tutorials use `aws s3 website` with public-read. This project enforces HTTPS, blocks S3 direct access entirely, and adds a real WAF — the pattern used in enterprise static hosting.

---

### P2 — Serverless Pipeline (Event-Driven Data Processing)

**One-sentence pitch:** Demonstrates a fully automated file-classification pipeline: upload a file → Lambda routes it by type → structured data goes to DynamoDB, unstructured files go through Textract/Rekognition, unknowns are quarantined.

**Key AWS services:** S3 (3 buckets), SQS (4 queues + DLQs), Lambda (3 functions), DynamoDB, API Gateway HTTP v2, Textract, Rekognition, CloudWatch + SNS

**What interviewers see:**
- You understand **SQS + DLQ retry logic**: 3 attempts → DLQ → CloudWatch alarm → SNS alert.
- You gave each Lambda **its own IAM role** (router-role, parser-role, extractor-role) with scoped permissions — not a single shared role for all functions.
- You handled the "unknown file type" case with a **quarantine bucket** — you thought about edge cases.
- You used **DynamoDB PAY_PER_REQUEST** + TTL — cost-aware design.

**Why it's non-trivial:** The routing logic at the Lambda layer (not just S3 prefix routing), separate roles per function, and the DLQ chain show systems thinking, not just "connect service A to service B."

---

### P3 — Smart Vault (Operational Automation + DR)

**One-sentence pitch:** Demonstrates automated EBS backup, retention management, and cross-region disaster recovery — the kind of runbook automation that ops teams build to eliminate manual snapshots.

**Key AWS services:** EventBridge (3 schedules), Lambda (3 functions), EBS snapshots, S3 (Seoul + Singapore with cross-region replication), API Gateway REST v1 (API key auth), CloudWatch + SNS

**What interviewers see:**
- You used both **`rate()` and `cron()` EventBridge expressions** — you know the difference and when each applies.
- You built **tag-based resource targeting** (`backup:true`) — the standard ops pattern for targeting infra without hardcoding resource IDs.
- You implemented **cross-region S3 replication** (Seoul → Singapore) for DR — multi-region awareness.
- The **`DRY_RUN = true` default** on cleanup shows production caution — you don't run destructive operations by default.
- You used **REST API Gateway with API key auth** (vs. HTTP v2 in P2/P4) — you know both variants and their trade-offs.

**Why it's non-trivial:** EBS snapshot automation with tag-based targeting and `RetainUntil` tag lifecycle is a real ops pattern. Cross-region replication for DR is something junior engineers skip.

---

### P4 — AI Chatbot (Flagship Integration)

**One-sentence pitch:** Demonstrates a production-grade customer service chatbot that stores multi-turn conversation history in DynamoDB, calls Google Gemini or AWS Bedrock interchangeably, and manages secrets through SSM — reusing the hosting, data, and alerting patterns from P1–P3.

**Key AWS services:** API Gateway HTTP v2, Lambda, DynamoDB (session history + TTL), SSM Parameter Store (SecureString + KMS), SNS (escalation), S3 + CloudFront (Web UI — P1 pattern), CloudWatch

**What interviewers see:**
- **SSM for secrets** — the Gemini API key never touches Terraform state, Lambda env console, or source code. An ADR documents the decision. This signals security-first thinking.
- **AI provider switching** via `AI_PROVIDER` env var — Gemini by default (free tier), switchable to Bedrock with one variable change. Shows operational flexibility.
- **Timeout layering**: Lambda timeout (45s) > Gemini timeout (25s), ensuring the history DynamoDB write always completes even if the AI call times out. A subtle but correct design.
- **Pattern reuse from P1–P3**: Web UI uses the P1 S3+CloudFront OAC pattern; session storage uses P2's DynamoDB PAY_PER_REQUEST+TTL pattern; escalation alerting uses P3's SNS pattern. This is the point of the portfolio arc — P4 shows you can compose.

**Why it's non-trivial:** The SSM cold-start caching, timeout layering, and provider-switching logic are production considerations that tutorial chatbots skip. The ADR for the secrets decision shows architectural thinking.

---

## Section 3 — Skills Coverage Matrix

| Skill Area | Level | Evidence |
|---|---|---|
| Terraform (IaC) | **Strong** | ~2,400 lines across 4 independent root modules; variables, outputs, IAM split into `iam.tf` |
| AWS Lambda | **Strong** | 7 functions in Python; separate roles per function; cold-start optimizations (SSM cache) |
| API Gateway | **Strong** | HTTP v2 (P2, P4) and REST v1 (P3); API key auth; CORS; custom access logging |
| S3 (advanced) | **Strong** | OAC, versioning, AES256, cross-region replication, lifecycle, public-access-block |
| CloudFront + WAF | **Strong** | WAF in us-east-1 for CloudFront global distribution; 4 managed rule groups |
| IAM (least privilege) | **Strong** | Scoped resource ARNs on all policies; per-function roles; no wildcards; no PassRole |
| DynamoDB | **Good** | PAY_PER_REQUEST, TTL auto-delete, session keying, batch writes |
| SQS + DLQ | **Good** | Retry logic (maxReceiveCount: 3), DLQ per queue, batch sizes tuned per Lambda |
| EventBridge | **Good** | rate() and cron() schedules; direct Lambda invocation |
| SNS + CloudWatch | **Good** | Metric alarms on error rates + DLQ depth; multi-region SNS (Seoul + us-east-1) |
| SSM / Secrets | **Good** | SecureString, KMS-encrypted, runtime fetch + container-lifetime cache; no plaintext in state |
| Textract / Rekognition | **Exposure** | Used in P2 extractor Lambda; shows AI service integration awareness |
| CI/CD (GitHub Actions) | **Weak** | Only runs `terraform init`; no plan/apply, no test gates, no approval workflow |
| Remote Terraform State | **Missing** | Local state only; no S3 backend + DynamoDB lock table |
| Infrastructure Testing | **Missing** | No Terratest, no pytest + moto for Lambdas, no integration tests |
| VPC / Networking | **Missing** | All managed services; no custom VPC, subnets, security groups, NAT Gateway |
| Containers (ECS/ECR) | **Missing** | No Docker, no ECS Fargate, no ECR |
| Blue/Green / Canary | **Missing** | No Lambda aliases with traffic shifting, no CodeDeploy |
| RDS / Aurora | **Missing** | Only DynamoDB; no relational database |
| Load Balancers | **Missing** | No ALB/NLB |

---

## Section 4 — Gap Priority (by mid-level interview impact)

These are the gaps that come up most in mid-level Cloud/DevOps interviews. Fix in this order.

### Gap 1 — Remote Terraform State (HIGH IMPACT)
**Why it matters:** Almost every interviewer asks "where does your Terraform state live?" Local state is immediately disqualifying for team contexts. S3 + DynamoDB locking is the standard answer.

**Fix:** Add a `backend "s3"` block to each project, create an S3 bucket + DynamoDB lock table as a bootstrap module, document the migration in an ADR.

**Effort:** ~2 hours per project; 1 day total.

---

### Gap 2 — CI/CD Depth (HIGH IMPACT)
**Why it matters:** The current workflow only runs `terraform init`. A mid-level engineer owns the CI/CD pipeline. Interviewers want to see: `terraform plan` on PRs (shows diff), `terraform apply` on merge (with manual approval gate).

**Fix:** Extend `.github/workflows/terraform-init.yml` to:
- PR: `terraform fmt -check`, `terraform validate`, `terraform plan` (output as PR comment)
- Merge to main: `terraform apply` (manual approval via GitHub Environment protection rule)

**Effort:** ~1 day.

---

### Gap 3 — Lambda Unit Tests (MEDIUM IMPACT)
**Why it matters:** "How do you test your Lambdas?" with no answer signals low code quality standards. pytest + moto (AWS mock library) is the standard Python answer.

**Fix:** Add `tests/` directory to P2 or P4, write 3–5 test cases for the router or chatbot Lambda using moto to mock S3/DynamoDB/SQS.

**Effort:** ~1 day for meaningful coverage.

---

### Gap 4 — VPC / Networking (MEDIUM IMPACT)
**Why it matters:** All current projects use managed services (no VPC needed). But "can you design a VPC?" is a core mid-level question. Custom VPC, public/private subnets, NAT Gateway, security groups, VPC endpoints — these are expected knowledge.

**Fix:** Add a P5 project (or extend P4) that places the Lambda inside a private VPC subnet, with a VPC endpoint for DynamoDB (no NAT needed for DynamoDB) and a NAT Gateway for Gemini HTTPS calls.

**Effort:** ~1–2 days.

---

### Gap 5 — Containers / ECS (LOWER IMPACT for serverless-focused portfolio)
**Why it matters:** ECS Fargate is increasingly common; Docker knowledge is assumed. Without it, the portfolio is serverless-only.

**Fix:** Containerize one Lambda (e.g., P4 chatbot) into an ECS Fargate task, push to ECR in CI, deploy via Terraform.

**Effort:** ~2–3 days.

---

## Section 5 — Interview Talking Points

### P1 — 90-second pitch
> "P1 is a static website where the S3 bucket has zero public access. All traffic goes through CloudFront, which authenticates to S3 using Origin Access Control — the current AWS best practice over the older Origin Access Identity. In front of CloudFront I deployed WAF with managed rule groups for SQL injection, XSS, and rate limiting. I also wired CloudWatch alarms to SNS so I'd get email alerts if 4xx or block rates spiked. One interesting Terraform detail: WAF for CloudFront must live in us-east-1 even when your S3 bucket is in Seoul, so I used a provider alias to manage both regions in one module."

**Likely follow-ups:**
- "Why OAC over OAI?" → OAI is deprecated; OAC supports S3 SSE-KMS and is the current AWS recommendation.
- "How does the WAF rate limit work?" → 2,000 requests per 5 minutes per IP; WAF evaluates rules in priority order.
- "What would you monitor in production?" → I already have CloudWatch alarms on 4xx >5%, 5xx >1%, WAF blocks >100/5min.

---

### P2 — 90-second pitch
> "P2 is a serverless data pipeline that auto-classifies files uploaded to S3. A router Lambda detects the file type and sends structured files (CSV, JSON) to one SQS queue and unstructured files (PDF, image) to another. Unknown types go to a quarantine bucket. Each queue has a DLQ: if processing fails 3 times, the message lands there and triggers a CloudWatch alarm. Each Lambda has its own IAM role with only the permissions it needs — the router can't write to DynamoDB, and the parser can't call Textract."

**Likely follow-ups:**
- "Why SQS between S3 and Lambda instead of direct S3→Lambda trigger?" → Decoupling: SQS buffers load spikes and provides the retry/DLQ mechanism; direct S3 triggers have no retry control.
- "What happens to quarantined files?" → They sit in a separate bucket; a human reviews them. The system never silently drops unknown types.
- "How do you handle DLQ messages?" → CloudWatch alarm fires → SNS email; I review the message, fix the Lambda, and replay.

---

### P3 — 90-second pitch
> "P3 automates EBS snapshots for any EC2 instance tagged `backup:true`. An EventBridge rule fires hourly, Lambda queries EC2 for tagged instances, creates snapshots, and adds a `RetainUntil` tag. A daily cleanup Lambda deletes expired snapshots. The cleanup defaults to DRY_RUN mode so it logs what it would delete without actually deleting — you have to explicitly flip the variable to enable real deletion. Cleanup logs are stored in S3 with cross-region replication to Singapore for DR. There's also a REST API with API key auth for on-demand restores."

**Likely follow-ups:**
- "Why tag-based targeting instead of hardcoding instance IDs?" → Tag-based targeting means the backup system works without changes when you add or remove instances.
- "Why DRY_RUN default?" → Destroying data should require explicit intent; defaulting to safe behavior means a misconfigured deploy won't accidentally delete snapshots.
- "What's the difference between rate() and cron() in EventBridge?" → `rate(1 hour)` runs on a fixed interval from the last run; `cron()` runs at an absolute UTC time — useful for "run at 9am KST every day."

---

### P4 — 90-second pitch
> "P4 is an AI customer service chatbot that ties together patterns from the first three projects. The web UI is hosted using P1's CloudFront+OAC pattern. Conversation history is stored in DynamoDB with a 24-hour TTL, using P2's PAY_PER_REQUEST design. Escalation alerts go through P3's SNS pattern. The chatbot calls Google Gemini by default, but you can switch to AWS Bedrock with one Terraform variable change. The Gemini API key lives in SSM Parameter Store as a KMS-encrypted SecureString — it never appears in Terraform state or the Lambda environment console. I documented that decision in an Architecture Decision Record."

**Likely follow-ups:**
- "Why SSM over Lambda environment variables?" → Env vars appear in the Lambda console in plaintext; SSM SecureString is KMS-encrypted at rest and only accessible to IAM principals you explicitly allow.
- "How does the conversation history work?" → Each request includes the last 10 turns from DynamoDB as context in the prompt. TTL auto-expires sessions after 24 hours.
- "What's the Lambda timeout strategy?" → Gemini has a 25-second timeout; I set Lambda to 45 seconds. This guarantees the DynamoDB history write completes even if Gemini times out — users get an error but don't lose their session.
