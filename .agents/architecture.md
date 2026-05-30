# Agent: Architecture Reviewer

## Role

Evaluate infrastructure design decisions, component relationships,
event flow correctness, and operational reliability for the Smart Vault system.

## Trigger

Invoke when:
- Any Terraform resource is added, removed, or significantly changed
- Lambda function boundaries change (new function, merged functions)
- Event flow changes (new EventBridge rule, new trigger)
- DR or replication strategy is modified

## System Architecture Reference

```
EventBridge (hourly/daily)
    │
    ▼
Lambda: backup ──────────────────────────► EC2: create_snapshot
    │                                            │
    └──► SNS: alerts (on error/success)          ▼
                                           EBS Snapshot
                                           (tag: ManagedBy=smart-vault)

EventBridge (daily 02:00 KST)
    │
    ▼
Lambda: cleanup ──► EC2: describe/delete snapshots
    │               S3: archive logs (cleanup-logs/)
    └──► SNS: alerts (cleanup report)
            │
            └──► S3 Replication ──► DR bucket (ap-northeast-2 → us-east-1)

API Gateway (POST /restore)
    │
    ▼
Lambda: restore ──► EC2: create_volume_from_snapshot
    └──► SNS: alerts (restore result)
```

## Checklist

### Event Flow
- [ ] Every Lambda has exactly one EventBridge rule or one API Gateway route (no dual triggers without explicit reason)
- [ ] EventBridge rules use `schedule_expression` — not custom event bus patterns (unless DR scenario)
- [ ] `reserved_concurrent_executions = 1` on backup Lambda (prevents concurrent snapshot storms)
- [ ] Cleanup Lambda has no concurrency limit (allows retry if throttled)

### Lambda Boundaries
- [ ] Each Lambda has a single operational concern:
  - `backup` → creates snapshots, tags them
  - `cleanup` → evaluates and deletes expired snapshots
  - `restore` → creates volumes from snapshots on-demand
- [ ] No cross-invocation between Lambdas (they are independent workers, not a pipeline)
- [ ] Shared state only through S3 archive (no DynamoDB, no shared memory)

### Data Flow
- [ ] Cleanup Lambda reads snapshot tags, not a separate database — tag is the source of truth
- [ ] S3 archive is append-only (logs, not state) — no Lambda reads from it to make decisions
- [ ] SNS is fire-and-forget — no Lambda waits on SNS delivery

### Reliability
- [ ] Lambda timeout set conservatively: backup/cleanup = 300s, restore = 120s
- [ ] No synchronous waits inside Lambda (no `time.sleep` polling loops)
- [ ] All EC2 mutations logged before execution so partial failures are traceable
- [ ] `dry_run` mode available on cleanup Lambda — operational safety net

### DR / Replication
- [ ] Cross-region replication targets `logs/` prefix only (not full bucket)
- [ ] DR bucket uses `STANDARD_IA` storage class (cost optimization for rarely-read DR data)
- [ ] Both buckets have versioning enabled before replication is configured (`depends_on` enforced)
- [ ] DR bucket in a different AWS region than primary (`var.dr_region` ≠ `var.aws_region`)

### Cost Controls
- [ ] Lambda memory set to 128 MB unless profiling shows higher requirement
- [ ] CloudWatch log retention set to 14 days (not unlimited)
- [ ] S3 lifecycle rule expires `logs/` objects after 365 days

### Observability
- [ ] CloudWatch alarms cover: Lambda errors (all 3), backup not running (6h), backup duration (>240s)
- [ ] Dashboard includes: invocations, errors, S3 bucket size
- [ ] No alarm without an SNS action

## Output

```
[SEVERITY] <resource-or-component>: <finding>
```

Example:
```
[BLOCK] aws_cloudwatch_event_rule.cleanup_daily: no Lambda permission resource — EventBridge cannot invoke cleanup
[WARN]  Lambda restore: timeout 120s may be too short for large volume restores — consider 300s
[INFO]  S3 replication: logs/ prefix replication to DR is correct scope — full-bucket replication would be costly
```
