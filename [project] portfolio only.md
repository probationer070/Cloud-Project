# Cloud Project — Technical Portfolio Deep-Dive (P1–P4)

> Engineer-facing analysis of the whole portfolio. For deploy/run instructions use each
> project's `README.md`; this document explains **what was built, how it works, and why**.
> Synthesized from the per-project `docs/design/*`, the Terraform sources, and the ADR/error
> records.

---

## 1. Overview

Four AWS projects, provisioned end-to-end with **Terraform** (no console clicking), each
**fully independent** — any project can be deployed or destroyed on its own, in any order.
The progression goes from a static edge-hardened site (P1) to an event-driven data pipeline
(P2), to a scheduled automation/DR system (P3), culminating in the flagship AI chatbot (P4),
which reuses the *code patterns* of the first three without depending on their deployed
infrastructure.

| | Project | One-line | Core stack |
|--|---------|----------|-----------|
| **P1** | Static Web | HTTPS-only static site, private origin behind WAF | S3 + CloudFront + WAF + CloudWatch + SNS |
| **P2** | Serverless Pipeline | Event-driven multi-format file ingestion | S3×3 + Lambda×3 + SQS×2(+DLQ) + DynamoDB + API GW + SNS |
| **P3** | Smart Vault | Scheduled EBS backup/restore with cross-region DR | EventBridge + Lambda×3 + EBS + S3×2 + API GW(REST) + SNS |
| **P4** ★ | AI Chatbot | Gemini-powered customer-service chatbot | API GW + Lambda + DynamoDB + SSM + SNS + S3 + CloudFront |

**Region footprint**
- Primary: `ap-northeast-2` (Seoul) for all compute/data.
- `us-east-1`: WAF Web ACL + ACM + CloudFront-scope alarms (CloudFront requires global scope).
- `ap-southeast-1` (Singapore): P3 cross-region DR replication target.

**What this portfolio demonstrates:** Terraform IaC discipline, least-privilege IAM design,
event-driven and scheduled serverless patterns, secrets management (SSM SecureString),
edge security (WAF/OAC), multi-region/DR, observability (CloudWatch + SNS), and a documented
engineering process (ADRs, change logs, error records, remote state).

---

## 2. Cross-Cutting Architecture & Engineering Practices

These patterns recur across all four projects and are the backbone of the portfolio.

### 2.1 Infrastructure as Code
Every project follows the same Terraform module layout:
```
projectN/
├── main.tf        # all infrastructure
├── iam.tf         # one least-privilege role per Lambda (P2/P3/P4)
├── variables.tf   # project_name, suffix, alert_email, tags, ...
├── outputs.tf     # endpoints + ready-to-run test commands
└── lambda/        # Python 3.12 handlers (P2/P3/P4)
```
Provider pinned to `hashicorp/aws ~> 5.0`, `required_version >= 1.5.0`. Bucket names are made
globally unique with a `suffix` variable.

### 2.2 Remote State Backend (shared)
State is centralized in S3 with **native S3 lockfile locking** (`use_lockfile = true`,
Terraform ≥ 1.10) — no DynamoDB lock table. Because a backend cannot be managed by a config
that *uses* it, a standalone `bootstrap/` config (own local state) provisions the bucket:

```
bootstrap/  → S3 bucket cloud-portfolio-tfstate-jaehwan-20260606
              (versioned, AES256, public-access-block ×4, TLS-only deny policy)

projectN/backend.tf → backend "s3" { bucket=..., key="projectN/terraform.tfstate",
                                      use_lockfile=true, encrypt=true }
```
Each project namespaces its state under a distinct `key`. **Ordering rule:** apply
`bootstrap/` before any project `terraform init`. See **ADR 0002** and **ERR-001** (the
local-state-not-shared incident that drove this decision).

### 2.3 Security Posture (recurring)
- **Least-privilege IAM per Lambda** — every Lambda gets its own role scoped to exact ARNs
  and actions; no shared wildcard role (P2/P3/P4 `iam.tf`).
- **Private S3 + CloudFront OAC** — origin buckets are never public; access only via the
  CloudFront service principal scoped by `AWS:SourceArn` (P1, P4).
- **Secrets in SSM SecureString** — P4's Gemini key is KMS-encrypted in Parameter Store,
  fetched once at cold start, never in Terraform state or the Lambda env tab (**ADR 0001**).
- **Encryption at rest** — AES256 SSE on all buckets including the state bucket.
- **Edge filtering** — P1 fronts CloudFront with WAF (managed rule sets + rate limit).
- **TLS-only** — the state bucket denies non-HTTPS access.

### 2.4 Observability (recurring)
Every project ships CloudWatch **alarms** + a **dashboard** + an **SNS email** path:
error-rate/5xx (P1), Lambda errors + DLQ depth (P2), missed-backup + duration (P3), Lambda
errors + response latency (P4). 5-minute aggregation; alarms notify on threshold breach.

### 2.5 Cost Discipline
Free-tier-first: DynamoDB `PAY_PER_REQUEST`, TTL auto-expiry to bound storage, S3 lifecycle
expiry, ARM64 Lambda. `force_destroy = true` on dev buckets (flagged as remove-before-prod).
Only genuinely paid items are P1 WAF managed rules (~$5–6/mo) and P3 EBS snapshots
($0.05/GB/mo) + cross-region replication.

### 2.6 Engineering Governance
- `.claude/CLAUDE.md` — coding/infra rules (simplicity, surgical changes, goal-driven).
- `.agents/` — focused review specs (security, refactoring, idea-management) with a decision
  matrix for when to consult each.
- `docs/changelog/` — every code/infra change logged with before/after.
- `docs/error/` — every confirmed bug recorded with root cause + prevention (e.g. ERR-001).
- `docs/adr/` — architecture decisions (0001 SSM credentials, 0002 remote state).

---

## 3. P1 — Security/Performance-Optimized Static Website

**Stack:** S3 + CloudFront + WAF + ACM (optional) + CloudWatch + SNS · **Region:** Seoul,
with WAF/ACM/alarms in `us-east-1`.

**Purpose:** globally distributed, HTTPS-only static hosting where the S3 origin is fully
private — reachable only through CloudFront via OAC — fronted by WAF.

```
User
  → WAF (CommonRuleSet SQLi/XSS, AmazonIpReputationList, RateLimit 2000/5min/IP)
  → CloudFront (HTTP→HTTPS redirect, TTL 1h/24h, 404/403 → index.html for SPA)
  → S3 (private, public-access-block all true, OAC-only)
        ↓
  CloudWatch (4xx>5%, 5xx>1%, WAF blocks>100/5min) → SNS → email
```

| Resource | Detail |
|----------|--------|
| S3 bucket | Private, versioning on, AES256 SSE |
| Bucket policy | `s3:GetObject` only to CloudFront service principal, scoped by `AWS:SourceArn` |
| WAF Web ACL | `CLOUDFRONT` scope: CommonRuleSet + IP reputation + 2000 req/5min/IP rate limit |
| CloudFront OAC | sigv4, `signing_behavior = always` |
| CloudFront dist | default root `index.html`, HTTPS redirect, SPA 404/403 rewrite |
| CloudWatch + SNS | error-rate/WAF alarms (Seoul + us-east-1 topics) + dashboard |

**IAM & security analysis:** there is *no* public access path — OAC + the `AWS:SourceArn`-scoped
bucket policy is the only way in; direct S3 URLs return 403 by design. WAF rejects malicious
traffic before it reaches the CDN. ACM is left commented out (default CloudFront cert until a
custom domain is added).

**Cost:** free-tier friendly; WAF managed rules (~$5–6/mo) are the only meaningful recurring
cost (disable WAF for ~$0 pure-dev).

---

## 4. P2 — Multi-Format Data Processing Serverless Pipeline

**Stack:** S3×3 + Lambda×3 + SQS×2 (+2 DLQ) + DynamoDB + API Gateway (HTTP v2) + SNS +
CloudWatch · **Region:** Seoul.

**Purpose:** event-driven ingestion — files land in S3 (or via API), a router classifies them,
structured data is parsed into DynamoDB, unstructured data (PDF/image) goes through
Textract/Rekognition. Failures isolate via DLQs + a quarantine bucket.

```
Upload (S3 ObjectCreated  or  POST /upload)
  → Router Lambda (by extension)
       ├─ csv/json  → structured SQS   → Parser Lambda    → DynamoDB
       ├─ pdf/image → unstructured SQS → Extractor Lambda → S3 processed
       └─ unknown   → S3 quarantine (tagged with reason)
  (each SQS: maxReceiveCount=3 → DLQ; errors → SNS email)
```

| Resource | Detail |
|----------|--------|
| S3 ingestion | `ObjectCreated` → triggers Router; AES256, private |
| S3 processed | Extraction output; lifecycle auto-delete after 90 days |
| S3 quarantine | Unknown/failed files with `reason` tags |
| SQS structured + DLQ | visibility 300s, retention 1d; DLQ 14d, maxReceiveCount 3 |
| SQS unstructured + DLQ | same config, isolated DLQ |
| DynamoDB `records` | PK `record_id`, GSI `source-key-index`, `PAY_PER_REQUEST`, TTL |
| Router Lambda | py3.12, 128MB/60s; routes by extension |
| Parser Lambda | py3.12, 256MB/300s; CSV/JSON validate → DynamoDB; SQS batch 10 |
| Extractor Lambda | py3.12, 512MB/300s; Textract/Rekognition; SQS batch 5 |
| API Gateway (HTTP v2) | `POST /upload` → Router (AWS_PROXY, payload v2.0) |

**Event flow internals:** the Router is the only synchronous-on-event component; everything
downstream is decoupled through SQS, so a slow/failing parser cannot back-pressure the
ingest. `maxReceiveCount=3` then DLQ gives bounded retries; the quarantine bucket captures
inputs the router can't classify, keeping the happy path clean.

**IAM & security analysis:** each of the three Lambdas has its own scoped role (`iam.tf`) —
the Router can enqueue but not write DynamoDB; the Parser writes DynamoDB but doesn't call
Textract; etc. All buckets private + AES256; quarantine isolates untrusted input.

**Cost:** effectively $0–1/mo on free tier (DynamoDB pay-per-request, Lambda/SQS free tier).

---

## 5. P3 — Smart Vault (Intelligent Automated Backup)

**Stack:** EventBridge + Lambda×3 + EC2/EBS snapshots + S3×2 (cross-region) + API Gateway
(REST v1) + SNS + CloudWatch · **Region:** Seoul (primary) + Singapore (DR).

**Purpose:** automated EBS backup/restore. EventBridge schedules snapshots of EC2 instances
tagged `backup:true`; a cleanup Lambda expires snapshots by their `RetainUntil` tag; cleanup
logs replicate cross-region; a key-protected REST endpoint restores a snapshot to a new EBS
volume.

```
EventBridge (hourly + daily 09:01 KST) → Backup Lambda
    → find EC2 tagged backup:true → create EBS snapshot (+ RetainUntil, ManagedBy tags)
    → SNS report email

EventBridge (daily 02:00 KST) → Cleanup Lambda
    → delete expired snapshots (DRY_RUN default true) → log to S3 archive (Seoul)
         → cross-region replication → S3 DR (Singapore, STANDARD_IA)

API Gateway POST /restore (API key) → Restore Lambda → new EBS volume from snapshot

CloudWatch alarms → SNS → email
```

| Resource | Detail |
|----------|--------|
| S3 archive (Seoul) | cleanup logs/metadata, AES256, versioned, 365-day lifecycle |
| S3 DR (Singapore) | replication target, STANDARD_IA, 400-day expiry |
| Replication role | scoped read on source + `s3:ReplicateObject` on dest |
| Backup Lambda | hourly + daily; tags `RetainUntil`/`ManagedBy=smart-vault`; ARM64 128MB/300s |
| Cleanup Lambda | daily; deletes expired snapshots, `DRY_RUN` toggle, logs to S3 |
| Restore Lambda | `POST /restore` (API key) → new EBS volume from snapshot |
| EventBridge | `rate(1 hour)`, `cron(1 0 * * ?)`, cleanup `cron(0 17 * * ?)` (KST 02:00) |
| API Gateway (REST) | `POST /restore`, API-key required, usage plan, stage `v1` |

**Notable internals:** the `RetainUntil` tag makes retention *data-driven* — Backup stamps an
expiry, Cleanup reads it; no separate retention DB. `DRY_RUN` defaults to **true** so the
first cleanup run only lists targets (safe by default). DR is achieved with native S3
cross-region replication of the `cleanup-logs/*` prefix to Singapore.

**IAM & security analysis:** least-privilege per Lambda; Restore validates
`snapshot_id`/`volume_type` before the EC2 call. `/restore` is guarded by `RESTORE_API_KEY`
(tfvars local-only, SSM for prod). EBS snapshots are intentionally **not** Terraform-managed —
delete them manually after testing.

**Cost:** EBS snapshots ($0.05/GB/mo) + cross-region replication ($0.02/GB) are the only paid
items — under $1 for a small test volume. Always `terraform destroy` after testing.

---

## 6. P4 — Customer-Service AI Chatbot ★ Flagship

**Stack:** API Gateway (HTTP v2) + Lambda + DynamoDB + SSM + SNS + S3 + CloudFront +
CloudWatch · **Region:** Seoul.

**Purpose:** a Gemini-API-based customer-service chatbot. Receives messages on a REST
endpoint, keeps conversation history in DynamoDB (24h TTL), returns AI responses, and emails
a human agent via SNS on escalation. Web UI served from S3 + CloudFront.

```
Browser / curl
  → CloudFront (HTTPS) ─ OAC ─▶ S3 (web UI, private)
  → API Gateway HTTP v2 (POST /chat)
       ▼
  Lambda chatbot (ARM64, 256MB, timeout 45s, Python 3.12)
  ┌──────────────────────────────────────────────┐
  │ 1. get_history   DynamoDB Query (last 10 turns)│
  │ 2. build_prompt  System Prompt + history + msg │
  │ 3. call_ai       Gemini API (HTTP 25s) | Bedrock│
  │ 4. route         ESCALATE / profanity / fallback│
  │ 5. save_history  DynamoDB BatchWriter (TTL 24h) │
  └──────────────────────────────────────────────┘
       │                    │
   DynamoDB             SSM Parameter Store (Gemini key, cold-start fetch)
   (sessions, TTL 24h)
       ▼ (on ESCALATE)
     SNS → email

CloudWatch (errors > 5/5min, response time > 10s) → SNS → email
```

| Resource | Detail |
|----------|--------|
| DynamoDB `p4-chatbot-sessions` | PK `session_id` (S), SK `timestamp` (S), `PAY_PER_REQUEST`, TTL 24h |
| SNS `p4-chatbot-alerts` | email subscription (escalation + alarms) |
| Lambda `p4-chatbot-chatbot` | ARM64, 256MB, timeout 45s, Python 3.12 |
| API Gateway HTTP v2 | `POST /chat`, CORS `allow_origins=["*"]` (restrict in prod) |
| S3 `p4-chatbot-ui-{suffix}` | web UI, private, AES256 SSE |
| CloudFront + OAC | HTTPS-only, `default_root_object=index.html`, 404→index.html |
| SSM Parameter Store | `/cloud-portfolio/gemini-api-key` (SecureString, KMS) — Terraform-managed placeholder (`ignore_changes=[value]`); real key seeded once via CLI |
| CloudWatch | error & latency alarms + dashboard |

### 6.1 Lambda 5-step flow
`get_history` → `build_prompt` → `call_gemini`/`call_bedrock` → `route_response` →
`save_history`. Step 4 detects the `ESCALATE` keyword (→ SNS publish), profanity (→ warning),
or timeout (→ fallback message).

### 6.2 DynamoDB conversation-history design — the `_0`/`_1` ordering invariant
Each turn stores a user + assistant item at the **same ISO timestamp**, disambiguated by a
sort-key suffix:
```
2026-06-05T14:23:45.123456+00:00_0  → role "user"
2026-06-05T14:23:45.123456+00:00_1  → role "assistant"
```
DynamoDB sorts the SK ascending, and `'0' < '1'`, so the user item always precedes the
assistant item. `get_history()` pairs items as `[user, assistant]`; this ordering is a
**precondition** of the pairing loop. The earlier `_user`/`_assistant` suffix broke it
(`'a' < 'u'` put assistant first), so multi-turn history mis-paired and fed the wrong context
to the AI — the repeated-response bug fixed in changelog `26-06-05`. Changing the suffix means
preserving this invariant.

### 6.3 AI provider switching
`ai_provider` toggles between Gemini (default, free Gemma 4 26B, 1,500 req/day) and Bedrock
(Claude 3 Haiku, us-east-1). Gemini-family models swap with only the `GEMINI_MODEL` env var —
no code change, same `call_gemini()` / `v1beta` endpoint.

### 6.4 Credentials & state (decisions)
- **SSM SecureString (ADR 0001):** the Gemini key never enters Terraform state or the Lambda
  env tab — fetched once at cold start, cached for the container lifetime. IAM grants
  `ssm:GetParameter` on the single parameter ARN only.
- **Remote state (ADR 0002 / ERR-001):** P4 was the first project migrated to the shared S3
  backend after a local-state-across-machines incident; it now uses `use_lockfile` locking.

**IAM & security analysis:** the Lambda role is scoped to the specific DynamoDB table, SNS
topic, and SSM parameter ARNs only. The Lambda's CORS response header is pinned to the
CloudFront origin via `ALLOWED_ORIGIN` (no wildcard), even though API Gateway CORS is `*`
(flagged to restrict in prod).

**Cost:** effectively $0/mo on free tier (Lambda/API GW/DynamoDB/SSM/S3+CloudFront/SNS all
within limits; Gemini free at ≤1,500 req/day). Bedrock switch ≈ $1–3/mo.

---

## 7. Cross-Project Pattern Reuse

P4 reuses the **code patterns** of P1–P3 but creates every resource itself — **no dependency
on their deployed infrastructure**. Each project deploys and destroys independently.

| Pattern source | Borrowed pattern | Where applied in P4 |
|----------------|------------------|---------------------|
| **P1** Static Web | S3 private + CloudFront OAC + HTTPS-only hosting | web UI (`main.tf` S3/CloudFront) |
| **P2** Pipeline | DynamoDB `PAY_PER_REQUEST` + TTL auto-expiry; API GW → Lambda AWS_PROXY | `p4-chatbot-sessions` + `POST /chat` |
| **P3** Smart Vault | SNS topic + email subscription notification | `p4-chatbot-alerts` escalation email |

> Independence is explicit in each design doc: P4's `main.tf` creates its own S3, CloudFront,
> DynamoDB, SNS, and API Gateway, so it works even if P1–P3 are never deployed.

---

## 8. Technology & Skills Matrix

| Capability | P1 | P2 | P3 | P4 |
|-----------|----|----|----|----|
| Terraform IaC | ✓ | ✓ | ✓ | ✓ |
| Python 3.12 Lambda | — | ✓×3 | ✓×3 | ✓ |
| Compute | — | Lambda | Lambda + EC2/EBS | Lambda (ARM64) |
| Data store | — | DynamoDB | EBS snapshots + S3 | DynamoDB (TTL) |
| Messaging/queue | — | SQS + DLQ | — | — |
| Eventing/schedule | — | S3 events | EventBridge cron | — |
| API | — | API GW HTTP | API GW REST (key) | API GW HTTP |
| Edge/CDN | CloudFront + WAF | — | — | CloudFront + OAC |
| AI/ML | — | Textract/Rekognition | — | Gemini / Bedrock |
| Secrets | — | — | API key (tfvars/SSM) | SSM SecureString |
| Multi-region/DR | us-east-1 (WAF) | — | Singapore DR | — |
| Least-privilege IAM | bucket policy | per-Lambda | per-Lambda | per-Lambda |
| Observability | CW + SNS | CW + SNS | CW + SNS | CW + SNS |

**Process skills:** ADR-driven decisions, change-log discipline, error records with
prevention, and a Terraform remote-state backend with locking.

---

## 9. References

- **Design docs:** [`docs/design/p1-static-web`](docs/design/p1-static-web/design.md) ·
  [`p2-serverless-pipeline`](docs/design/p2-serverless-pipeline/design.md) ·
  [`p3-smart-vault`](docs/design/p3-smart-vault/design.md) ·
  [`p4-ai-chatbot`](docs/design/p4-ai-chatbot/design.md)
- **ADRs:** [`0001 — SSM Parameter Store for credentials`](docs/adr/0001-ssm-parameter-store-for-api-credentials.md) ·
  [`0002 — S3 Remote State Backend`](docs/adr/0002-s3-remote-state-backend.md)
- **Error records:** [`ERR-001 — local state not shared across machines`](docs/error/ERR-001-local-state-not-shared-across-machines.md)
- **Remote backend setup:** [`bootstrap/README.md`](bootstrap/README.md)
- **Operational guides:** each `projectN/README.md` and `file-structure.md`
- **Governance:** [`.agents/README.md`](.agents/README.md) · `.claude/CLAUDE.md`
