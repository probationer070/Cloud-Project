# P1 Design — Static Web (Security/Performance-Optimized Static Website)

**Directory:** `project1-static-web/`
**Stack:** S3 + CloudFront + WAF + ACM (optional) + CloudWatch + SNS
**Region:** `ap-northeast-2` (Seoul); WAF/ACM/alarms in `us-east-1` (CloudFront requirement)

## Purpose

Globally distributed, HTTPS-only static site hosting. The S3 origin is fully
private — reachable only through CloudFront via Origin Access Control (OAC) —
fronted by WAF for SQLi/XSS and rate-limit protection.

## Architecture

```
User → CloudFront (WAF attached) ──OAC──> S3 (private)
                │
                └── CloudWatch alarms ─→ SNS ─→ email
```

## Resource Inventory

| Resource | Detail | Source |
|----------|--------|--------|
| S3 bucket | Private (public-access-block all true), versioning on, AES256 SSE | `main.tf:31-88` |
| Bucket policy | `s3:GetObject` allowed only to CloudFront service principal scoped by `AWS:SourceArn` | `main.tf:67-88` |
| WAF Web ACL | `CLOUDFRONT` scope: CommonRuleSet, AmazonIpReputationList, RateLimit 2000/5min/IP | `main.tf:112-199` |
| CloudFront OAC | sigv4, `signing_behavior = always` | `main.tf:205-211` |
| CloudFront dist | default root `index.html`, HTTP→HTTPS redirect, 404/403→`index.html` (SPA), TTL 1h/24h | `main.tf:217-282` |
| CloudWatch alarms | 4xx > 5%, 5xx > 1%, WAF blocked > 100/5min | `main.tf:289-354` |
| SNS | Seoul + us-east-1 topics, email subscription | `main.tf:360-383` |
| Dashboard | Requests, error rate, cache hit rate, WAF blocks | `main.tf:389-476` |

## Security Notes

- S3 is never public; OAC + bucket policy is the only access path.
- `force_destroy = true` is a test/dev convenience — remove before production.
- ACM block is commented out; default CloudFront cert is used until a custom domain is added.

## Cost

Free-tier friendly; WAF managed rules are the main recurring cost (~$5–6/mo) — disable WAF to reach ~$0 in pure dev.

## Usage

### Prerequisites
Terraform must already be applied (`terraform apply` from `project1-static-web/`).

### 1. Confirm outputs
```powershell
cd project1-static-web
terraform output
```
This prints the bucket name, CloudFront distribution ID, and the ready-to-run commands below.

### 2. Add your files
Place HTML/CSS/JS in `project1-static-web/website/`. `index.html` is already there as a placeholder.

### 3. Upload to S3
```powershell
aws s3 sync ./website/ s3://<bucket_name>/ --delete
# aws s3 sync ./website/ s3://p1-static-web-jaehwan-20260527/ --delete
```
`--delete` removes S3 objects no longer present locally.

### 4. Invalidate CloudFront cache
```powershell
aws cloudfront create-invalidation --distribution-id <dist_id> --paths "/*"
# aws cloudfront create-invalidation --distribution-id E28GYOHPUO7JUU --paths "/*"
```
Get `<dist_id>` from `terraform output cloudfront_distribution_id`.

### 5. Access the site
```powershell
terraform output cloudfront_domain
```
Open the printed URL. **Never use the S3 URL directly** — the bucket is private; direct access returns 403 by design.

---

## How P4 reuses this

P4 hosts its chatbot web UI on this **S3 + CloudFront** pattern: private bucket,
OAC origin, HTTPS-only delivery, and the same CloudWatch alarm/SNS wiring for
front-end monitoring. P4's `website/index.html` deploys the same way
(`aws s3 sync` + CloudFront invalidation).

> **Infrastructure independence:** P4 does not reference P1's deployed resources. In P4's
> `main.tf` it creates its own S3 bucket and CloudFront distribution directly. P4 works
> correctly even if P1 is never deployed.
