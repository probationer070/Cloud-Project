# P3 Design — Smart Vault (Intelligent Automated Backup)

**Directory:** `project3-smart-vault/`
**Stack:** EventBridge + Lambda ×3 + EC2/EBS snapshots + S3 ×2 (cross-region) + API Gateway (REST) + SNS + CloudWatch
**Region:** `ap-northeast-2` (Seoul, primary) + `ap-southeast-1` (Singapore, DR)

## Purpose

Automated EBS backup and restore. EventBridge schedules snapshot creation for
EC2 instances tagged `backup:true`; a cleanup Lambda expires snapshots by their
`RetainUntil` tag; cleanup logs replicate cross-region to a DR bucket; a
key-protected REST endpoint restores a snapshot to a new EBS volume.

## Resource Inventory

| Resource | Detail | Source |
|----------|--------|--------|
| S3 archive | cleanup logs/metadata, AES256, versioned, 365-day lifecycle | `main.tf:30-117` |
| S3 DR (Singapore) | cross-region replication target, STANDARD_IA, 400-day expiry | `main.tf:30-181` |
| Replication role | scoped read on source + `s3:ReplicateObject` on dest | `iam.tf` |
| Backup Lambda | EventBridge hourly + daily; snapshots tagged `RetainUntil`/`ManagedBy=smart-vault`; ARM64, 128MB/300s | `lambda/backup/index.py` |
| Cleanup Lambda | daily; deletes expired snapshots, `DRY_RUN` toggle, logs to S3 | `lambda/cleanup/index.py` |
| Restore Lambda | `POST /restore` (API key) → new EBS volume from snapshot | `lambda/restore/index.py` |
| EventBridge | hourly `rate(1 hour)`, daily `cron(1 0 * * ?)`, cleanup `cron(0 17 * * ?)` (KST 02:00) | `main.tf:316-378` |
| API Gateway (REST) | `POST /restore`, API-key required, usage plan, stage `v1` | `main.tf:384-459` |
| CloudWatch | per-Lambda error alarms, backup-not-running alarm, duration alarm | `main.tf:465-521` |

## Security Notes

- Each Lambda role is least-privilege (`iam.tf`); restore validates `snapshot_id`/`volume_type` before the EC2 call.
- `RESTORE_API_KEY` is the only auth on `/restore` — tfvars local-only, SSM for prod.
- EBS snapshots are **not** Terraform-managed; delete them manually after testing.

## Cost

EBS snapshots are the only paid item ($0.05/GB/mo) + cross-region replication ($0.02/GB) — under $1 for a small test volume. Run `terraform destroy` after testing.

## How P4 reuses this

P4 borrows P3's **SNS email-notification pattern** for agent handoff: when the
chatbot detects an escalation request, it publishes to an SNS topic that emails
a human agent — the same topic/subscription wiring P3 uses for backup reports.

> **Infrastructure independence:** P4 does not reference P3's deployed resources. In P4's
> `main.tf` it creates its own SNS topic directly. P4 works correctly even if P3 is never deployed.

---

> The sections below were the original root `README.md` for P3, preserved here.

## Architecture
```
[EventBridge scheduler]
  Hourly          ───────────────────────────┐
  Daily midnight  ────────────────────────┐  │
  Daily 02:00 (KST) ──────────┐           │  │
                              │           │  │
                       Cleanup Lambda   Backup Lambda
                  Delete expired snapshots   ↓
                              │      EC2 (backup:true tag)
                              │           ↓
                              │      Create EBS snapshot (incremental)
                              │           ↓
                              │      Auto-attach tags
                              │     (date / environment / RetainUntil)
                              ↓
                    S3 archive bucket ──→ S3 DR bucket (cross-region)
                              ↓
                       SNS notification → email

[API Gateway]
  POST /restore ──→ Restore Lambda ──→ Create new EBS volume
```

## File Layout
```
project3-smart-vault/
├── main.tf               # full infrastructure
├── iam.tf                # least privilege per Lambda
├── variables.tf
├── outputs.tf            # includes test commands
└── lambda/
    ├── backup/index.py   # backup:true tagged instances → create snapshots
    ├── cleanup/index.py  # delete expired snapshots by RetainUntil
    └── restore/index.py  # snapshot → restore new EBS volume
```

## Estimated Cost
| Service | Free tier | Cost over limit |
|--------|-----------|----------|
| Lambda | 1M requests/mo | none |
| EventBridge | unlimited schedules | none |
| S3 archive | 5 GB | none |
| EBS snapshots | none (billed per GB) | **$0.05/GB/mo** |
| Cross-region replication | none | **$0.02/GB** |
| SNS | 1,000 free | none |

> ⚠️ **EBS snapshots are the only paid item** — under $1 for a small test volume.
> Always run `terraform destroy` after testing.

---

## Deployment Steps

### 1. Edit variables.tf
```hcl
suffix          = "yourname-20250527"
alert_email     = "your@email.com"
cleanup_dry_run = true   # keep true for a safe first test
retention_days  = 7
```

### 2. Deploy
```bash
terraform init
terraform plan
terraform apply
```

---

## Test Order

### Step 1. Add the backup tag to an EC2 instance
```bash
# Replace with your own EC2 instance ID
aws ec2 create-tags \
  --resources i-xxxxxxxxxxxxxxxxx \
  --tags Key=backup,Value=true \
  --region ap-northeast-2
```
> If you have no EC2 instance: AWS Console → EC2 → Launch instance (t2.micro / Free Tier)

### Step 2. Run the Backup Lambda manually
```bash
# Run the test_manual_backup command from outputs
aws lambda invoke \
  --function-name p3-smart-vault-backup \
  --payload '{"schedule":"manual-test"}' \
  --region ap-northeast-2 \
  /tmp/backup-result.json && cat /tmp/backup-result.json
```

### Step 3. Verify snapshot creation
```bash
# Run the check_snapshots command from outputs
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters Name=tag:ManagedBy,Values=smart-vault \
  --region ap-northeast-2 \
  --query 'Snapshots[*].{ID:SnapshotId,Name:Tags[?Key==`Name`]|[0].Value,RetainUntil:Tags[?Key==`RetainUntil`]|[0].Value}' \
  --output table
```

### Step 4. Test the Cleanup Lambda (DRY RUN)
```bash
# Runs with cleanup_dry_run = true — lists targets only, no actual deletion
aws lambda invoke \
  --function-name p3-smart-vault-cleanup \
  --region ap-northeast-2 \
  /tmp/cleanup-result.json && cat /tmp/cleanup-result.json
```

### Step 5. Test the Restore API
```bash
# Replace with the snapshot_id confirmed in Step 3
curl -X POST [restore_api_endpoint] \
  -H "Content-Type: application/json" \
  -d '{
    "snapshot_id": "snap-xxxxxxxx",
    "volume_type": "gp3",
    "availability_zone": "ap-northeast-2a"
  }'
```

### Step 6. Verify DR replication
```bash
# Verify Seoul → Singapore replication
aws s3 ls s3://[dr-archive-bucket]/ --recursive --region ap-southeast-1
```

---

## Validation Checklist
- [ ] Snapshot auto-created for backup:true tagged EC2
- [ ] Snapshot has RetainUntil / BackupDate tags
- [ ] Cleanup Lambda DRY RUN output verified
- [ ] Restore API creates a new EBS volume
- [ ] Cleanup log stored in S3 archive
- [ ] Cross-region replication to DR bucket confirmed
- [ ] Backup completion report received by email
- [ ] CloudWatch dashboard Lambda invocation graph confirmed

---

## Destroy Resources
```bash
# Empty both S3 buckets
aws s3 rm s3://[archive-bucket] --recursive
aws s3 rm s3://[dr-archive-bucket] --recursive --region ap-southeast-1

terraform destroy
```

> ⚠️ EBS snapshots are not managed by Terraform — delete them manually in the console:
> EC2 → Snapshots → filter ManagedBy=smart-vault → select all → Delete
