![Terraform CI](https://github.com/probationer070/Cloud-Project/actions/workflows/terraform-ci.yml/badge.svg?branch=main)

# Cloud Project — AWS Hands-On Portfolio (P1–P4)

Four AWS projects provisioned with Terraform.

**Each project is fully independent** — none depends on another's deployed infrastructure, and each can be deployed or destroyed on its own, in any order.
**P4 (AI Chatbot)** reuses the Terraform patterns (code structure) of P1–P3, but provisions every resource it needs (S3, CloudFront, DynamoDB, SNS, etc.) on its own. **You do NOT need to deploy P1, P2, or P3 to test P4.**

**Shared Terraform state:** the [`bootstrap/`](bootstrap/README.md) config creates one S3 bucket for remote state — apply it once. **P4 uses it** via `backend.tf` (S3 + native lockfile locking); P1–P3 currently still use local state. The bucket is the only cross-project prerequisite; the projects still share no application infrastructure. See [ADR-0002](docs/adr/0002-s3-remote-state-backend.md).

> **Development environment setup** → [`CONTRIBUTING.md`](CONTRIBUTING.md) — local init (`init-all.ps1` / `init-all.sh`), AWS credentials, CI workflow

---

## P1 — Security/Performance-Optimized Static Website

**Goal:** HTTPS-only static hosting that keeps S3 private and serves content exclusively through CloudFront + WAF.

```
User request
    → WAF (SQLi/XSS blocking, IP reputation filter, 2000 req/5min rate limit)
    → CloudFront (HTTPS enforced, cache TTL 1h, 404/403 → index.html)
    → S3 (private bucket, OAC access only)
         ↓
    CloudWatch alarms (4xx>5%, 5xx>1%, WAF blocks>100/5min)
         → SNS → email
```

| AWS Service | Role | When it runs |
|-----------|------|-----------|
| S3 | Static file storage (private) | Accessible only on CloudFront OAC requests |
| CloudFront | CDN · HTTPS enforcement · SPA routing | Every user request |
| WAF (us-east-1) | SQLi/XSS blocking, IP reputation, rate limiting | Before requests reach CloudFront |
| CloudWatch | Error-rate / WAF block-count monitoring | 5-min aggregation; alarms when thresholds are exceeded |
| SNS (Seoul + us-east-1) | Sends alarm emails | On CloudWatch alarm state transitions |

📄 [Design doc](docs/design/p1-static-web/design.md) · [File structure](project1-static-web/file-structure.md)

---

## P2 — Multi-Format Data Processing Serverless Pipeline

**Goal:** An event-driven pipeline that automatically classifies → parses → extracts → stores CSV/JSON/PDF/image files as soon as they are uploaded to S3.

```
File upload (S3 ObjectCreated  or  POST /upload)
    → Router Lambda (routes by file extension)
         ├─ csv/json  → Structured SQS   → Parser Lambda    → DynamoDB
         ├─ pdf/image → Unstructured SQS → Extractor Lambda → S3 processed
         └─ unknown   → S3 quarantine
    (3 failures → DLQ → CloudWatch alarm → SNS → email)
```

| AWS Service | Role | When it runs |
|-----------|------|-----------|
| S3 ingestion | Receives uploads | ObjectCreated → triggers Router Lambda |
| S3 processed | Stores pypdf/Rekognition results (auto-deleted after 90 days) | When Extractor Lambda completes |
| S3 quarantine | Isolates unsupported/failed files | On Router/Parser/Extractor errors |
| SQS structured queue + DLQ | Buffers CSV/JSON; 3 failures → DLQ | When Router sends a message |
| SQS unstructured queue + DLQ | Buffers PDF/image | When Router sends a message |
| Lambda Router | Detects file extension → sends to queue or quarantine | On S3 ObjectCreated event |
| Lambda Parser | Validates CSV/JSON → stores in DynamoDB | SQS structured queue (batch 10) |
| Lambda Extractor | pypdf (PDF text) / Rekognition (image) → stores in S3 | SQS unstructured queue (batch 5) |
| DynamoDB | Stores parsed result records (`PAY_PER_REQUEST`, TTL) | When Parser/Extractor completes |
| API Gateway (HTTP v2) | External file-intake endpoint `POST /upload` | On external client calls |
| CloudWatch | Monitors Lambda errors and DLQ depth | 5-min aggregation; alarms when thresholds are exceeded |
| SNS | Processing-failure notification emails | On CloudWatch alarm or Lambda error |

📄 [Design doc](docs/design/p2-serverless-pipeline/design.md) · [File structure](project2-serverless-pipeline/file-structure.md)

---

## P3 — Intelligent Automated Backup (Smart Vault)

**Goal:** A fully automated backup system that snapshots, manages retention for, and restores the EBS volumes of EC2 instances tagged `backup:true`. Includes Singapore DR replication.

```
EventBridge (hourly / daily 09:01 KST) → Backup Lambda
    → Find EC2 instances tagged backup:true
    → Create EBS snapshot + attach RetainUntil tag
    → SNS report email

EventBridge (daily KST 02:00) → Cleanup Lambda
    → Delete expired snapshots (supports DRY_RUN mode)
    → Write log to S3 archive (Seoul)
         → Cross-region replication to S3 DR (Singapore)

API Gateway POST /restore (API key auth) → Restore Lambda
    → Snapshot → create new EBS volume

CloudWatch alarms → SNS → email
```

| AWS Service | Role | When it runs |
|-----------|------|-----------|
| EventBridge (hourly) | Periodically runs Backup Lambda | `rate(1 hour)` |
| EventBridge (daily) | Runs Backup Lambda daily | `cron(1 0 * * ?)` UTC = KST 09:01 |
| EventBridge (cleanup) | Runs Cleanup Lambda | `cron(0 17 * * ?)` UTC = KST 02:00 |
| Lambda Backup | Finds EC2 → creates EBS snapshots | EventBridge schedule |
| Lambda Cleanup | Deletes expired snapshots + writes logs | EventBridge schedule (DRY_RUN defaults to true) |
| Lambda Restore | Snapshot → new EBS volume | On `POST /restore` API call |
| EBS snapshots | Incremental backup data | Created by Backup, expired by Cleanup, used by Restore |
| S3 archive (Seoul) | Stores Cleanup logs | When Cleanup Lambda completes |
| S3 DR (Singapore) | Cross-region disaster-recovery replica | S3 replication rule (`cleanup-logs/*`, STANDARD_IA) |
| API Gateway (REST v1) | `POST /restore` — API key auth required | On manual restore requests |
| CloudWatch | Monitors Lambda errors, missed backups, execution timeouts | On threshold breach or no invocation within 6 hours |
| SNS | Backup report / error notification emails | On Lambda execution results and CloudWatch alarms |

📄 [Design doc](docs/design/p3-smart-vault/design.md) · [File structure](project3-smart-vault/file-structure.md)

---

## P4 — Customer-Service AI Chatbot ★ Flagship

**Goal:** A customer-service chatbot with a pluggable AI provider (Google Gemini API by default, Amazon Bedrock / Claude optional — switch via the `AI_PROVIDER` env var). API Gateway + Lambda 5-step processing, DynamoDB conversation history (24h TTL), SNS notification on agent escalation. Reuses P1/P2/P3 patterns.

```
Browser / curl
    → API Gateway (POST /chat)
    → Lambda chatbot
         ├─ 1. Fetch DynamoDB conversation history (last 10 turns)
         ├─ 2. Build prompt (System Prompt + history + current message)
         ├─ 3. Call AI provider (Gemini by default / Bedrock optional; Gemini key fetched once from SSM at cold start)
         ├─ 4. Validate/route response (normal · escalation · profanity · fallback)
         └─ 5. Save DynamoDB conversation history (TTL 24h)
              ↓ (on escalation detected)
            SNS → email notification

Web UI: CloudFront → S3 (reuses P1 pattern)
CloudWatch alarms (errors · response latency over 10s) → SNS → email
```

| AWS Service | Role | When it runs |
|-----------|------|-----------|
| API Gateway (HTTP v2) | `POST /chat` REST endpoint | On user message submission |
| Lambda chatbot | 5-step chatbot core logic | On API Gateway invocation (timeout 45s, ARM64) |
| DynamoDB `p4-chatbot-sessions` | Stores per-session conversation history (auto-expires at TTL 24h) | Read/written on every Lambda invocation |
| SSM Parameter Store | Holds the Gemini API key (SecureString, KMS-encrypted). Terraform creates it as a `PLACEHOLDER`; the real key is seeded once via CLI after apply (`ignore_changes` keeps apply from overwriting it) | Fetched once at Lambda cold start, then cached for the container lifetime |
| Gemini API / Amazon Bedrock (external) | Generates AI responses — Gemini (HTTP timeout 25s) or Bedrock/Claude via `bedrock-runtime`, selected by `AI_PROVIDER` | On every Lambda invocation |
| SNS | Email notification for agent-handoff requests | When ESCALATE is detected in the response |
| S3 | Hosts web UI static files (private, OAC) | On CloudFront requests |
| CloudFront | Serves web UI over HTTPS, CORS origin source | On browser access |
| CloudWatch | Monitors Lambda error count / response time | 5-min aggregation; alarms when thresholds are exceeded |

**Patterns referenced from P1–P3 (code patterns only — no infra dependency):**
- **P1 →** S3 + CloudFront (OAC) web-UI hosting pattern (P4 creates its own S3/CloudFront resources)
- **P2 →** DynamoDB `PAY_PER_REQUEST` + TTL auto-expiry pattern (P4 creates its own DynamoDB table)
- **P3 →** SNS email-notification pattern (P4 creates its own SNS topic)

📄 [Design doc](docs/design/p4-ai-chatbot/design.md) · [File structure](project4-ai-chatbot/file-structure.md) · [P4 build plan](docs/todo.md) · [ADR: SSM credentials](docs/adr/0001-ssm-parameter-store-for-api-credentials.md) · [ADR: S3 remote state](docs/adr/0002-s3-remote-state-backend.md)

---

## Repository Structure

```
Cloud Project/
├── bootstrap/                    # one-time: creates the shared S3 state bucket used by P4 (ADR-0002)
├── project1-static-web/          # P1 infra + website
├── project2-serverless-pipeline/ # P2 infra + Lambda
├── project3-smart-vault/         # P3 infra + Lambda
├── project4-ai-chatbot/          # P4 infra + Lambda + web UI (backend.tf → S3 remote state)
├── docs/
│   ├── design/                   # P1/P2/P3 design docs
│   ├── adr/                      # Architecture Decision Records
│   ├── todo.md                   # P4 full build plan
│   ├── changelog/                # change log (records every code change)
│   ├── error/                    # bug records
│   └── refactoring-*.md          # refactoring reference docs
├── .agents/                      # sub-agent specs (refactoring · idea-management · security)
├── init-all.ps1 / init-all.sh    # terraform init across all projects
├── tf-all.ps1                    # run init/plan/apply/destroy across all projects
├── CONTRIBUTING.md               # dev environment setup
└── 정리자료/                     # blog notes, hand-written (do not modify)
```

## Common Workflow

1. Identify the change type → pick an agent from the decision matrix in [`.agents/README.md`](.agents/README.md)
2. Coding / infra guidelines → [`.claude/CLAUDE.md`](.claude/CLAUDE.md)
3. Every code change → must be recorded in `docs/changelog/`
4. Every confirmed bug → must be recorded in `docs/error/`

## Deployment

**One-time — create the shared state bucket** (needed for P4's remote backend):

```bash
cd bootstrap
terraform init
terraform apply        # creates the S3 state bucket; bootstrap keeps its own local state
```

**Per project** — from each project directory:

```bash
terraform init         # P4 configures the S3 backend; P1–P3 use local state
terraform plan
terraform apply
# after testing
terraform destroy
```

> **P4 only:** after `apply`, seed the real Gemini API key into SSM once — Terraform
> creates the parameter as a `PLACEHOLDER` (see [ADR-0001](docs/adr/0001-ssm-parameter-store-for-api-credentials.md)):
> ```bash
> aws ssm put-parameter --name /cloud-portfolio/gemini-api-key --type SecureString --overwrite --value "YOUR_KEY"
> ```

**Across all projects at once** (Windows): `./tf-all.ps1 <init|plan|apply|destroy> [project]` — runs against every `project*` directory, with a confirmation gate for `apply`/`destroy`. `init-all.ps1` / `init-all.sh` run just `init`.

For detailed deployment and testing steps, see each project directory's `README.md` and `file-structure.md`.
