# 26-05-31 [bug] Project3 EC2 No Default VPC subnet_id Missing

**Type:** bug
**Branch / Commit:** Testo / 4dc6529

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project3-smart-vault/main.tf` | `aws_instance.backup_target` | Added `subnet_id = aws_subnet.test.id` |
| `project3-smart-vault/main.tf` | `aws_vpc.test` (new) | Minimal test VPC (`10.0.0.0/16`) |
| `project3-smart-vault/main.tf` | `aws_subnet.test` (new) | Test subnet (`10.0.1.0/24`, AZ `ap-northeast-2a`) |

## Why Changed

`terraform apply` on project3-smart-vault failed with:

```
Error: creating EC2 Instance: operation error EC2: RunInstances,
api error VPCIdNotSpecified: No default VPC for this user.
GroupName is only supported for EC2-Classic and default VPC.
  with aws_instance.backup_target, on main.tf line 587
```

`aws_instance.backup_target` had no `subnet_id`. EC2 falls back to the account
default VPC when `subnet_id` is omitted, but the AWS account has no default VPC
in `ap-northeast-2`. This is a follow-on issue from the previous fix
(`26-05-31 [bug] Project3 Dead VPC Data Sources Blocking Plan.md`) which removed
the dead `data.aws_vpc.default` blocks without adding an explicit subnet.

Discovered during Phase 0 validation run via `.\tf-all.ps1 apply p3`.

## Contents Diff

**`project3-smart-vault/main.tf`**
```hcl
# Before
resource "aws_instance" "backup_target" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  # no subnet_id → relies on default VPC (does not exist)
  tags = { ... }
}

# After
resource "aws_vpc" "test" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "smart-vault-test-vpc", ManagedBy = "terraform" }
}

resource "aws_subnet" "test" {
  vpc_id            = aws_vpc.test.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "smart-vault-test-subnet", ManagedBy = "terraform" }
}

resource "aws_instance" "backup_target" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.test.id   # explicit — no default VPC dependency
  tags = { ... }
}
```

## Improvements

- EC2 instance launches successfully without requiring an account default VPC
- VPC and subnet are fully managed by Terraform — `terraform destroy` removes them
- Self-contained: no AWS CLI prerequisites or manual account setup required
- Minimal infrastructure intentionally: no IGW, no route table, no public IP.
  The EC2 is a backup test target only, not publicly reachable.

## Performance Impact

- `terraform apply` on project3 now completes without error
- Adds 2 new resources to project3 state (vpc, subnet)

## Agents Consulted

security

## Findings Addressed

- [BLOCK] EC2 instance failed to create due to missing subnet and no default VPC.
  Fixed by creating a self-contained VPC + subnet within the project.

## Findings Deferred

none
