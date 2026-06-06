# 26-05-31 [bug] Project3 Dead VPC Data Sources Blocking Plan

**Type:** bug
**Branch / Commit:** Testo / 4dc6529

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project3-smart-vault/main.tf` | `data.aws_vpc.default`, `data.aws_subnets.default` | Removed both unused data source blocks (lines 577–586) |

## Why Changed

`terraform plan` on project3-smart-vault failed with:

```
Error: no matching EC2 VPC found
  with data.aws_vpc.default,
  on main.tf line 577, in data "aws_vpc" "default":
  577: data "aws_vpc" "default" {
```

The AWS account has no default VPC in `ap-northeast-2`. The two data source
blocks (`data.aws_vpc.default` and `data.aws_subnets.default`) were defined
but never referenced by any resource — `aws_instance.backup_target` has no
`subnet_id` attribute and does not use either data source. Dead code causing
a hard plan failure.

Discovered during Phase 0 validation run using `.\tf-all.ps1 plan`.

## Contents Diff

**`project3-smart-vault/main.tf`**
```hcl
# Before (lines 576–586)
# Use the account's default VPC/subnet
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# After
# (removed — both blocks were unreferenced)
```

## Improvements

- `terraform plan` on project3-smart-vault no longer fails
- No functional change to `aws_instance.backup_target` — EC2 launches into
  the account default subnet when `subnet_id` is omitted, which is unchanged

## Performance Impact

- Plan failure eliminated — project3 now completes plan successfully

## Agents Consulted

security

## Findings Addressed

- [WARN] Dead data sources (`data.aws_vpc.default`, `data.aws_subnets.default`)
  referenced no resources but caused hard plan failure. Removed.

## Findings Deferred

none
