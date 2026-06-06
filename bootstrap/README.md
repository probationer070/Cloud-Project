# bootstrap/ — Terraform Remote State Backend

This config provisions the **shared S3 bucket** that stores Terraform remote state for every
project (P1–P4). It exists to break the chicken-and-egg problem: the state backend can't be
managed by a config that already *uses* it, so `bootstrap/` keeps its **own local state** and
is applied once, on its own.

State **locking** uses native S3 lockfiles (`use_lockfile = true` in each project's
`backend.tf`, Terraform ≥ 1.10) — there is no DynamoDB table.

## ⚠️ Ordering rule — run this BEFORE any project `terraform init`

```powershell
cd bootstrap
terraform init
terraform apply        # creates s3://cloud-portfolio-tfstate-jaehwan-20260606
```

Only after the bucket exists can a project migrate to the remote backend:

```powershell
cd ..\project4-ai-chatbot
terraform init         # migrates state into the bucket
terraform apply
```

## Using the bucket from a project

Each project's `backend.tf` hardcodes the bucket name (backend blocks can't read
variables) and a unique `key`:

```hcl
terraform {
  backend "s3" {
    bucket       = "cloud-portfolio-tfstate-jaehwan-20260606"
    key          = "project4-ai-chatbot/terraform.tfstate"   # per-project namespace
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
```

The bucket name is also emitted as the `state_bucket` output of this config.

## Troubleshooting

- **`Error: ... S3 bucket "..." does not exist` / `NoSuchBucket` on `terraform init`** —
  you skipped this bootstrap, or ran it against a different account/region. Run
  `terraform apply` here first, then retry the project's `init`. (The failed `init` is safe:
  Terraform leaves both source and destination state unmodified.)
- **Switching a project that was already init'd** — `terraform init -reconfigure`.

## Notes

- The bucket is versioned (state rollback), AES256-encrypted, fully private
  (public-access-block ×4), and denies non-TLS access.
- This config's own state stays local — it changes rarely and holds no application secrets.
- Background: see `docs/adr/0002-s3-remote-state-backend.md` and `docs/error/ERR-001-*`.
