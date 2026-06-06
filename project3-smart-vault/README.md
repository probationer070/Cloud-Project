# Project 3: Smart Vault (Automated EBS Backup)

> **Standalone project** — P1, P2, and P4 do not need to be deployed.
> **EC2 instance required** — the Backup Lambda looks for EC2 instances tagged `backup=true`. A Free Tier t2.micro is sufficient.

## Architecture

```
EventBridge (hourly / daily midnight) → Backup Lambda
    → Find EC2 instances tagged backup=true
    → Create EBS snapshot + attach RetainUntil tag
    → SNS report email

EventBridge (daily KST 02:00) → Cleanup Lambda
    → Delete expired snapshots (dry-run safe when DRY_RUN=true)
    → Write log to S3 archive (Seoul)
         → Replicate to S3 DR (Singapore)

API Gateway POST /restore (API key auth) → Restore Lambda
    → Snapshot → new EBS volume

CloudWatch alarms (errors, 6h no invocation) → SNS → email
```

## Estimated Cost

| Service | Free Tier | Note |
|---------|-----------|------|
| Lambda | 1M requests/mo | free |
| EventBridge | unlimited schedules | free |
| S3 archive | 5 GB | free |
| EBS snapshots | none | **$0.05/GB/mo** |
| Cross-region replication | none | **$0.02/GB** |
| SNS | 1,000 notifications | free |

> EBS snapshots are the only paid item. Under **$1** for small test volumes. Always destroy after testing.

---

## Deployment Steps

### Step 1. (Prerequisite) Tag an EC2 Instance for Backup

If you don't have an EC2 instance, create a t2.micro Free Tier instance in the AWS Console first.

**Windows (PowerShell):**
```powershell
# Replace with your actual EC2 instance ID
aws ec2 create-tags `
  --resources i-xxxxxxxxxxxxxxxxx `
  --tags Key=backup,Value=true `
  --region ap-northeast-2
```
**Linux / macOS:**
```bash
# Replace with your actual EC2 instance ID
aws ec2 create-tags \
  --resources i-xxxxxxxxxxxxxxxxx \
  --tags Key=backup,Value=true \
  --region ap-northeast-2
```

### Step 2. Edit variables.tf

```hcl
suffix          = "yourname-20260527"  # ← unique suffix for S3 bucket names (required)
alert_email     = "your@email.com"     # ← alarm notification email (required)
cleanup_dry_run = true                 # ← keep true for first test run (safe)
retention_days  = 7                    # ← snapshot retention period in days
```

### Step 3. Deploy Infrastructure

```powershell
cd project3-smart-vault
terraform init
terraform plan
terraform apply
```

After `terraform apply` completes, note the outputs:

```
archive_bucket       = "p3-smart-vault-archive-..."
dr_archive_bucket    = "p3-smart-vault-dr-..."
restore_api_endpoint = "https://xxxxx.execute-api.ap-northeast-2.amazonaws.com/v1/restore"
dashboard_url        = "https://..."
```

### Step 4. Confirm SNS Email Subscription

An **"AWS Notification - Subscription Confirmation"** email will arrive at `alert_email`.
**Click "Confirm subscription".**

---

## Test Scenarios

> Run `terraform output` to see the test commands pre-filled with your actual resource names.

### 1. Trigger Backup Lambda Manually

**Windows (PowerShell):**
```powershell
# Run the test_manual_backup output command
aws lambda invoke `
  --function-name p3-smart-vault-backup `
  --payload '{"schedule":"manual-test"}' `
  --region ap-northeast-2 `
  backup-result.json
Get-Content backup-result.json
```
**Linux / macOS:**
```bash
# Run the test_manual_backup output command
aws lambda invoke \
  --function-name p3-smart-vault-backup \
  --payload '{"schedule":"manual-test"}' \
  --region ap-northeast-2 \
  backup-result.json
cat backup-result.json
```

Expected: `{"statusCode": 200, "snapshots_created": 1, ...}`

### 2. Verify Snapshot Created

**Windows (PowerShell):**
```powershell
# Run the check_snapshots output command
aws ec2 describe-snapshots `
  --owner-ids self `
  --filters Name=tag:ManagedBy,Values=smart-vault `
  --region ap-northeast-2 `
  --query 'Snapshots[*].{ID:SnapshotId,RetainUntil:Tags[?Key==`RetainUntil`]|[0].Value}' `
  --output table
```
**Linux / macOS:**
```bash
# Run the check_snapshots output command
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters Name=tag:ManagedBy,Values=smart-vault \
  --region ap-northeast-2 \
  --query 'Snapshots[*].{ID:SnapshotId,RetainUntil:Tags[?Key==`RetainUntil`]|[0].Value}' \
  --output table
```

A snapshot with a `RetainUntil` tag confirms the backup ran correctly.

### 3. Cleanup Lambda Dry Run

**Windows (PowerShell):**
```powershell
# Run the test_manual_cleanup output command
# With cleanup_dry_run = true, no snapshots are actually deleted
aws lambda invoke `
  --function-name p3-smart-vault-cleanup `
  --region ap-northeast-2 `
  cleanup-result.json
Get-Content cleanup-result.json
```
**Linux / macOS:**
```bash
# Run the test_manual_cleanup output command
# With cleanup_dry_run = true, no snapshots are actually deleted
aws lambda invoke \
  --function-name p3-smart-vault-cleanup \
  --region ap-northeast-2 \
  cleanup-result.json
cat cleanup-result.json
```

### 4. Verify S3 Archive Log

```powershell
# Run the check_archive_logs output command
aws s3 ls s3://[archive_bucket]/cleanup-logs/ --recursive
```

### 5. Verify DR Replication (Seoul → Singapore)

```powershell
# Run the check_dr_replication output command
aws s3 ls s3://[dr_archive_bucket]/ --recursive --region ap-southeast-1
```

Files uploaded to the Seoul archive bucket replicate to Singapore within a few minutes.

### 6. Restore API Test

Get the snapshot ID from Step 2. The API key is a sensitive value — retrieve it via `terraform output`.

**Windows (PowerShell):**
```powershell
# Retrieve the API key
$API_KEY = terraform output -raw restore_api_key_value

# Send restore request (replace snapshot_id with a real value from Step 2)
Invoke-RestMethod `
  -Uri "[restore_api_endpoint]" `
  -Method POST `
  -ContentType "application/json" `
  -Headers @{"x-api-key" = $API_KEY} `
  -Body '{"snapshot_id": "snap-xxxxxxxxxxxxxxxxx", "volume_type": "gp3", "availability_zone": "ap-northeast-2a"}'
```
**Linux / macOS:**
```bash
# Retrieve the API key
API_KEY=$(terraform output -raw restore_api_key_value)

# Send restore request (replace snapshot_id with a real value from Step 2)
curl -X POST "[restore_api_endpoint]" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"snapshot_id": "snap-xxxxxxxxxxxxxxxxx", "volume_type": "gp3", "availability_zone": "ap-northeast-2a"}'
```
**Windows (curl.exe):**
```powershell
# Retrieve the API key
$API_KEY = terraform output -raw restore_api_key_value

curl.exe -X POST "[restore_api_endpoint]" `
  -H "Content-Type: application/json" `
  -H "x-api-key: $API_KEY" `
  -d '{\"snapshot_id\": \"snap-xxxxxxxxxxxxxxxxx\", \"volume_type\": \"gp3\", \"availability_zone\": \"ap-northeast-2a\"}'
```

Expected: `{"statusCode": 200, "volume_id": "vol-...", ...}`

### 7. CloudWatch Dashboard

```
Open dashboard_url from terraform output
→ Check Lambda invocation count, error count, duration graphs
```

---

## Validation Checklist

- [ ] `terraform output` shows `restore_api_endpoint` and `archive_bucket`
- [ ] SNS subscription confirmation email received → clicked "Confirm subscription"
- [ ] EC2 instance with `backup=true` tag has a new snapshot with `RetainUntil` tag
- [ ] Cleanup Lambda dry-run output lists target snapshots (no actual deletion)
- [ ] Cleanup log file appears in S3 archive bucket
- [ ] Log file replicated to DR bucket in Singapore
- [ ] Restore API creates a new EBS volume
- [ ] CloudWatch dashboard shows Lambda invocation graph
- [ ] Backup report email received at `alert_email`

---

## Common Errors

**No snapshots created**
→ Verify the EC2 instance has a tag with Key=`backup`, Value=`true` (exact case)
→ Verify the Lambda IAM role has `ec2:DescribeInstances` and `ec2:CreateSnapshot`

**Restore API returns 403**
→ Missing or incorrect `x-api-key` header
→ Re-fetch the key: `terraform output -raw restore_api_key_value`

**DR replication not appearing in Singapore**
→ Replication only applies to newly uploaded objects, not existing ones
→ Trigger the Cleanup Lambda again to generate a new log file

---

## Destroy Resources

```powershell
# 1. Empty both S3 buckets
aws s3 rm s3://[archive_bucket] --recursive
aws s3 rm s3://[dr_archive_bucket] --recursive --region ap-southeast-1

# 2. Destroy Terraform resources
terraform destroy
```

> **EBS snapshots are NOT managed by Terraform — delete them manually:**
> AWS Console → EC2 → Snapshots → filter `ManagedBy = smart-vault` → select all → Delete
