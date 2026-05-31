# Contributing — Developer Setup

This guide covers everything you need to get from a fresh clone to running Terraform commands
on any of the 4 projects in this repo.

---

## Prerequisites

| Tool | Required version | Install |
|------|-----------------|---------|
| Terraform | >= 1.5.0 | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | >= 2.x | [docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Git | any recent | [git-scm.com](https://git-scm.com) |

**AWS credentials:** You need an IAM user or role with permissions for the services each project
uses. Set credentials with one of:

```bash
# Option 1 — environment variables
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

# Option 2 — named profile
aws configure --profile my-profile
export AWS_PROFILE=my-profile

# Option 3 — instance role / GitHub Actions OIDC (CI only)
# No manual configuration needed — the role is assumed automatically
```

Default region is `ap-northeast-2` (Seoul). You can override it per project via `variables.tf`.

---

## First-Time Setup

Each of the 4 projects is an independent Terraform root module. Terraform must be initialized
in each directory before you can run `plan` or `apply`. The init scripts do this in one command.

### Windows (PowerShell)

```powershell
# From the repo root
./init-all.ps1
```

Requires PowerShell 5.1 or later (built into Windows 10/11). No additional tools needed.

### Linux, macOS, or WSL

```bash
# From the repo root, or from any directory
bash init-all.sh
```

### What the scripts do

Both scripts:
1. Locate `project*/` directories that contain a `main.tf` file
2. Run `terraform init -input=false` in each one
3. Abort immediately and print the failing directory name if any init fails
4. Print a success count on completion

```
=== Initializing project1-static-web ===
Initializing the backend...
...
=== Initializing project2-serverless-pipeline ===
...
=== All 4 projects initialized ===
```

After a successful init, each project directory will contain a `.terraform/` folder and a
`.terraform.lock.hcl` file. The lock file is committed to git — this pins provider versions
across all machines and CI.

---

## Per-Project Workflow

After initialization, work inside each project directory directly:

```bash
cd project4-ai-chatbot

# Preview changes
terraform plan

# Apply (deploys to AWS)
terraform apply

# Destroy (tears down all resources)
terraform destroy
```

Projects are fully independent. Destroying P4 has no effect on P1–P3.

| Project | Description | Key AWS services |
|---------|-------------|-----------------|
| `project1-static-web` | HTTPS static site with WAF | S3, CloudFront, WAF, ACM |
| `project2-serverless-pipeline` | File processing pipeline | S3, SQS, Lambda, DynamoDB, API GW |
| `project3-smart-vault` | Secrets management layer | Secrets Manager, SSM, Lambda, API GW |
| `project4-ai-chatbot` | AI chatbot (flagship) | Bedrock, Lambda, API GW, DynamoDB |

---

## CI

Pushing to `main` or `Testo` — or opening a pull request — triggers the
[Terraform Init](../.github/workflows/terraform-init.yml) workflow on GitHub Actions.

The workflow:
1. Checks out the repo
2. Installs the latest stable Terraform
3. Restores the provider plugin cache (keyed on `main.tf` + lock file hashes)
4. Runs `bash init-all.sh` across all 4 projects

The provider cache means subsequent CI runs skip the ~200MB AWS provider download and finish
significantly faster.

To reproduce the CI environment locally:

```bash
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
bash init-all.sh
```

---

## Re-initializing After Provider Changes

If you update a provider version in a `main.tf` file, run:

```bash
cd <project-dir>
terraform init -upgrade
```

Then commit the updated `.terraform.lock.hcl`:

```bash
git add project4-ai-chatbot/.terraform.lock.hcl
git commit -m "chore: upgrade AWS provider lock for project4"
```

---

## Phase 2: Terragrunt (planned)

The dual-script approach is a bridge. A future branch will replace both scripts with:

```bash
terragrunt run-all init
```

Terragrunt also enables `run-all plan` and `run-all apply` across all projects.
Prerequisites for Phase 2: migrate all projects to a remote backend (S3 + DynamoDB).
See `docs/changelog/26-05-31 [upgrade] One Command Terraform Init All Projects.md` for context.
