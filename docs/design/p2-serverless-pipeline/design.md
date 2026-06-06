# P2 Design — Serverless Pipeline (Multi-Format Data Processing Pipeline)

**Directory:** `project2-serverless-pipeline/`
**Stack:** S3 ×3 + Lambda ×3 + SQS ×2 (+2 DLQ) + DynamoDB + API Gateway (HTTP) + SNS + CloudWatch
**Region:** `ap-northeast-2` (Seoul)

## Purpose

Event-driven ingestion pipeline. Files land in S3 (or via API), a router
classifies them, structured data is parsed into DynamoDB, and unstructured data
(PDF/image) is sent through Textract/Rekognition. Failures are isolated via DLQs
and a quarantine bucket.

## Architecture

```
Upload (S3 ObjectCreated  or  POST /upload)
        ▼
   Router Lambda ── csv/json ─→ structured SQS ─→ Parser Lambda ─→ DynamoDB
        │          pdf/img   ─→ unstructured SQS ─→ Extractor Lambda ─→ S3 processed
        └── unknown ─→ quarantine bucket
   (each SQS has a DLQ, maxReceiveCount=3 → DLQ; errors → SNS email)
```

## Resource Inventory

| Resource | Detail | Source |
|----------|--------|--------|
| S3 ingestion | Triggers Router on `ObjectCreated`, AES256, private | `main.tf:34-54, 253-270` |
| S3 processed | Extraction output; lifecycle auto-delete after 90 days | `main.tf:57-89` |
| S3 quarantine | Unknown/failed files with `reason` tags | `main.tf:92-111` |
| SQS structured + DLQ | visibility 300s, retention 1d; DLQ 14d, maxReceiveCount 3 | `main.tf:118-134` |
| SQS unstructured + DLQ | same config, isolated DLQ | `main.tf:137-153` |
| DynamoDB `records` | PK `record_id`, GSI `source-key-index`, `PAY_PER_REQUEST`, TTL on `ttl` | `main.tf:159-187` |
| Router Lambda | py3.12, 128MB/60s; routes by file extension | `main.tf:231-250` |
| Parser Lambda | py3.12, 256MB/300s; CSV/JSON validate → DynamoDB; SQS-triggered batch 10 | `main.tf:273-299` |
| Extractor Lambda | py3.12, 512MB/300s; Textract/Rekognition; SQS-triggered batch 5 | `main.tf:302-329` |
| API Gateway (HTTP v2) | `POST /upload` → Router (AWS_PROXY, payload v2.0) | `main.tf:335-369` |
| CloudWatch | per-Lambda error alarms, DLQ-depth alarms, dashboard | `main.tf:376-493` |
| IAM | one least-privilege role per Lambda | `iam.tf` |

## Security Notes

- Each Lambda has its own scoped role (`iam.tf`); no shared wildcard role.
- All buckets private with AES256; quarantine isolates untrusted input.
- `force_destroy = true` on all three buckets — test/dev only.

## Cost

Effectively $0–1/mo on free tier (DynamoDB pay-per-request, Lambda/SQS free tier).

## How P4 reuses this

P4 borrows P2's **DynamoDB pattern** for conversation history:
`PAY_PER_REQUEST` billing, a string partition key, and **TTL-based auto-expiry**
(P2 uses `ttl`; P4's `p4-chatbot-sessions` uses a 24-hour `ttl` for cost control).
P2's API-Gateway-to-Lambda (AWS_PROXY) wiring is the same model P4 uses for its
`POST /chat` endpoint.

> **Infrastructure independence:** P4 does not reference P2's deployed resources. In P4's
> `main.tf` it creates its own DynamoDB table and API Gateway directly. P4 works correctly
> even if P2 is never deployed.
