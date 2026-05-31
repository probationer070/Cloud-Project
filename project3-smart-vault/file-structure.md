# P3 File Structure — Smart Vault

```
project3-smart-vault/
│
├── main.tf               # S3 ×2 (archive Seoul + DR Singapore),
│                         #   cross-region replication, SNS, Lambda ×3,
│                         #   EventBridge schedules ×3,
│                         #   API Gateway REST (v1, API-key auth),
│                         #   CloudWatch alarms + test EC2 instance
│
├── iam.tf                # Four roles:
│                         #   backup-role, cleanup-role, restore-role
│                         #   + s3-replication-role
│                         #   Shared local.log_policy — scoped to each
│                         #   Lambda's specific CloudWatch log group ARNs
│
├── variables.tf          # aws_region, dr_region, project_name, suffix,
│                         #   alert_email, retention_days,
│                         #   cleanup_dry_run, common_tags
│
├── outputs.tf            # Test commands: manual backup invoke,
│                         #   cleanup DRY RUN, restore API curl
│
├── lambda/
│   ├── backup/
│   │   └── index.py      # Queries EC2 by backup:true tag;
│   │                     #   creates EBS snapshots with RetainUntil tag;
│   │                     #   reports via SNS
│   ├── cleanup/
│   │   └── index.py      # Deletes snapshots past RetainUntil;
│   │                     #   DRY_RUN env var for safe testing;
│   │                     #   logs to S3 archive
│   └── restore/
│       └── index.py      # POST /restore (API key required);
│                         #   creates new EBS volume from snapshot
│
└── myplan.tfplan         # Saved terraform plan (not gitignored locally)
```

## Key relationships

- EventBridge triggers Backup Lambda hourly (`rate(1 hour)`) and daily (`cron(1 0 * * ?)`).
- EventBridge triggers Cleanup Lambda daily at UTC 17:00 = KST 02:00 (`cron(0 17 * * ?)`).
- Backup Lambda uses `architectures = ["arm64"]` (Graviton2) — also Cleanup and Restore.
- `local.log_policy` in `iam.tf` is shared across all three Lambda roles, scoped to their specific log group ARNs.
- Cross-region replication copies `cleanup-logs/*` from Seoul archive bucket to Singapore DR bucket (`STANDARD_IA` class).
- `cleanup_dry_run = true` by default — must be explicitly set to `false` to enable actual snapshot deletion.
- EBS snapshots are **not** Terraform-managed resources; destroy requires manual console deletion after `terraform destroy`.

## Design reference

[Full architecture, cost, and deployment guide](../docs/design/p3-smart-vault/design.md)
