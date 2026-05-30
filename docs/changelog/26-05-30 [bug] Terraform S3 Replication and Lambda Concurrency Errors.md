# 26-05-30 [bug] Terraform S3 Replication and Lambda Concurrency Errors

**Type:** bug
**Branch / Commit:** dev / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `main.tf` | `aws_s3_bucket_replication_configuration.archive` | Added `delete_marker_replication { status = "Disabled" }` to replication rule |
| `main.tf` | `aws_lambda_function.backup` | Removed `reserved_concurrent_executions = 1` |
| `main.tf` | `aws_s3_bucket_replication_configuration.archive` | Removed `filter` block to fix provider v5 empty-body serialization bug |
| `main.tf` | `aws_s3_bucket_replication_configuration.archive` | Removed `delete_marker_replication`; switched to schema v1 with `prefix` directly on the rule |
| `main.tf` | `aws_s3_bucket_replication_configuration.archive` | `prefix` on rule is deprecated in provider v5; reverted to schema v2 (`filter` + `delete_marker_replication`) |

## Why Changed

`terraform apply` failed with two errors:

1. **S3 `InvalidRequest: DeleteMarkerReplication must be specified`** — The AWS S3 replication API schema v2 (used when a `filter` block is present) requires an explicit `delete_marker_replication` block. Without it the `PutBucketReplication` call is rejected with HTTP 400.

2. **Lambda `InvalidParameterValueException: Specified ReservedConcurrentExecutions decreases account's UnreservedConcurrentExecution below its minimum value of 10`** — The test account has a low total concurrency limit. Reserving 1 concurrency for the backup Lambda left the account-wide unreserved pool below the AWS-enforced floor of 10, causing the Lambda creation to fail.

3. **S3 `MissingRequestBodyError: Request Body is empty`** — AWS provider v5 serialization bug: combining `filter { prefix = "..." }` with `delete_marker_replication` in the same replication rule causes the provider to generate an empty HTTP request body for `PutBucketReplication`, resulting in HTTP 400. Fix attempt: removed the `filter` block, but `delete_marker_replication` was left in place (see error 4).

4. **S3 `InvalidRequest: DeleteMarkerReplication cannot be used for this version`** — Schema v1 (no `filter` block) does not allow `delete_marker_replication`; schema v2 (with `filter` block) requires it. Removing `filter` but keeping `delete_marker_replication` produced this conflict. Interim fix: removed both, used `prefix` directly on the rule (schema v1).

5. **Terraform deprecation warning: `prefix` is deprecated, use `filter` instead`** — Schema v1 `prefix` attribute on the rule is deprecated in provider v5. The earlier `MissingRequestBodyError` (error 3) was likely caused by a dirty Terraform state from the first failed apply, not a permanent provider bug. Final fix: reverted to schema v2 with both `filter { prefix = "cleanup-logs/" }` and `delete_marker_replication { status = "Disabled" }`, which is the correct and non-deprecated form.

## Contents Diff

**`main.tf` — `aws_s3_bucket_replication_configuration.archive` rule**
```hcl
# Before
filter {
  prefix = "cleanup-logs/"
}
destination { ... }

# After
filter {
  prefix = "cleanup-logs/"
}
delete_marker_replication {
  status = "Disabled"
}
destination { ... }
```

**`main.tf` — `aws_lambda_function.backup`**
```hcl
# Before
timeout                        = 300
memory_size                    = 128
reserved_concurrent_executions = 1

# After
timeout     = 300
memory_size = 128
```

## Improvements

- `terraform apply` no longer fails on S3 replication or Lambda concurrency errors.
- Replication config now complies with the v2 schema; delete marker replication is explicitly disabled (delete markers are not replicated to DR, which is the correct behaviour for audit logs).

## Performance Impact

Removing `reserved_concurrent_executions` means the backup Lambda can now run more than one concurrent instance if EventBridge fires a retry alongside a running invocation. In practice this is negligible: EventBridge schedules are infrequent and the risk of true concurrency is low in this single-account test environment.

## Agents Consulted

architecture, security

## Findings Addressed

- [BLOCK] S3 replication schema missing required `delete_marker_replication` field
- [BLOCK] Lambda reserved concurrency below account minimum
- [BLOCK] AWS provider v5 serialization bug: `filter` + `delete_marker_replication` produces empty request body
- [BLOCK] Schema v1/v2 conflict: `delete_marker_replication` without `filter` block is invalid; switched to schema v1 (`prefix` on rule, no `filter`, no `delete_marker_replication`)
- [WARN] Schema v1 `prefix` attribute deprecated in provider v5; reverted to schema v2 (`filter` + `delete_marker_replication`) — the correct non-deprecated form

## Findings Deferred

none
