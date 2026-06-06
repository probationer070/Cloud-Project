# Project 1: Secure Static Website (S3 + CloudFront + WAF)

> **Standalone project** — P2, P3, and P4 do not need to be deployed.

## Architecture

```
User request
    → WAF Web ACL (SQLi/XSS block, IP reputation, rate limit 2000req/5min)
    → CloudFront (HTTPS enforced, cache TTL 1h, 404/403 → index.html)
    → S3 (private bucket, accessible only via CloudFront OAC)
         ↓
    CloudWatch alarms (4xx > 5%, 5xx > 1%, WAF blocks > 100/5min)
         → SNS → email
```

## Estimated Cost

| Service | Free Tier | Note |
|---------|-----------|------|
| S3 | 5 GB / 20,000 GET | free |
| CloudFront | 1 TB transfer | free |
| WAF | none | **~$5–6/mo (Web ACL)** |
| CloudWatch | 10 alarms | free |
| SNS | 1,000 notifications | free |

> Disabling WAF brings the cost to ~$0/mo. Always `terraform destroy` after testing.

---

## Deployment Steps

### Step 1. Edit variables.tf

```hcl
bucket_name = "p1-static-web-yourname-20260527"  # ← globally unique name (required)
alert_email = "your@email.com"                    # ← alarm notification email (required)
```

### Step 2. Deploy Infrastructure

```powershell
cd project1-static-web
terraform init
terraform plan    # review ~15 resources to be created
terraform apply   # type "yes"
```

> CloudFront deployment takes **5–10 minutes**. Wait for it to complete before the next step.

After `terraform apply` completes, note the outputs:

```
cloudfront_domain          = "https://d1234abcd.cloudfront.net"
cloudfront_distribution_id = "E28GYOHPUO7JUU"
s3_bucket_name             = "p1-static-web-yourname-20260527"
upload_command             = "aws s3 sync ./website/ s3://.../ --delete"
```

### Step 3. Confirm SNS Email Subscription

An **"AWS Notification - Subscription Confirmation"** email will arrive at `alert_email` right after `apply`.
**Click "Confirm subscription"** — without this, alarm emails will not be sent.

### Step 4. Upload Static Files to S3

```powershell
# Run the upload_command from Step 2
aws s3 sync ./website/ s3://[s3_bucket_name]/ --delete
```

Place your HTML/CSS/JS files in the `website/` folder. `index.html` is the default entry point.

### Step 5. Open in Browser

```
Open the cloudfront_domain URL from Step 2
e.g. https://d1234abcd.cloudfront.net
```

> **Direct S3 URL returns 403** — the bucket is private by design.

---

## Test Scenarios

### 1. HTTPS Access

Open `cloudfront_domain` in a browser → page loads correctly.

### 2. HTTP → HTTPS Redirect

**Windows (curl.exe):**
```powershell
curl.exe -I http://d1234abcd.cloudfront.net
# Expected: HTTP/2 301 → Location: https://...
```
**Linux / macOS:**
```bash
curl -I http://d1234abcd.cloudfront.net
# Expected: HTTP/2 301 → Location: https://...
```

### 3. S3 Direct Access Block (Security Check)

AWS Console → S3 → bucket → select a file → copy "Object URL" → open in browser
→ **403 AccessDenied** is the correct response (OAC security working).

### 4. CloudFront Cache Invalidation (After File Updates)

**Windows (PowerShell):**
```powershell
aws cloudfront create-invalidation `
  --distribution-id [cloudfront_distribution_id] `
  --paths "/*"
```
**Linux / macOS:**
```bash
aws cloudfront create-invalidation \
  --distribution-id [cloudfront_distribution_id] \
  --paths "/*"
```

### 5. CloudWatch Dashboard

```
Open cloudwatch_dashboard_url from terraform output
→ Check request count, error rate, cache hit rate, WAF block graphs
```

---

## Validation Checklist

- [ ] `terraform output` shows `cloudfront_domain` and `s3_bucket_name`
- [ ] SNS subscription confirmation email received → clicked "Confirm subscription"
- [ ] CloudFront URL loads over HTTPS
- [ ] HTTP → HTTPS redirect returns 301
- [ ] S3 direct URL returns 403 AccessDenied
- [ ] CloudWatch dashboard shows request count graph

---

## Common Errors

**S3 bucket name already exists**
→ Change `bucket_name` to a more unique value (include your name and date)

**CloudFront 403 after deploy**
→ Verify files were uploaded in Step 4
→ If files are present, run a CloudFront cache invalidation

**WAF rule error (AWSManagedRulesManagedRuleSet)**
→ Comment out the `AWSManagedRulesAmazonIpReputationList` block in `main.tf` and retry

---

## Destroy Resources

```powershell
# 1. Empty S3 bucket (destroy fails if files remain)
aws s3 rm s3://[s3_bucket_name] --recursive

# 2. Destroy Terraform resources
terraform destroy
```

> WAF deletion can take several minutes. Retry if it errors out.
