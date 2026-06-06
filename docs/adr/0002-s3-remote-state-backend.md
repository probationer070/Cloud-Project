# ADR 0002 — S3 Remote State Backend with Native Lockfile Locking

**Date:** 2026-06-06
**Status:** Accepted

## Context

P4 (and P1–P3) used Terraform's default **local state** — `terraform.tfstate` on the
operator's disk. The project is developed across two machines (a laptop and a desktop)
under the same AWS account, and the `.tf` configuration is synced between them via git.

Terraform state is gitignored (`*.tfstate`, `*.tfstate.*`) because it can contain
plaintext secrets, so git syncs only the configuration — **never the state**. This produced
a concrete failure (ERR-001): the laptop deployed P4's full 22-resource stack, but the
desktop's state was empty. Running `terraform apply` on the desktop tried to *create*
resources that already existed in the shared account, failing with five `*AlreadyExists`
errors (IAM role, DynamoDB table, CloudWatch log group, S3 bucket, CloudFront OAC).

Local state has two structural problems for this workflow:

1. **Not shareable.** State lives on one machine; any second machine sees an empty/stale
   state and re-creates or orphans live resources.
2. **No locking.** Two machines (or a machine and CI) can `apply` concurrently and corrupt
   state with interleaved writes.

## Decision

Move all Terraform state to an **S3 remote backend with native lockfile locking**, shared
across every project.

- **State storage:** one S3 bucket `cloud-portfolio-tfstate-jaehwan-20260606`, with each
  project namespaced by a distinct `key` (P4 → `project4-ai-chatbot/terraform.tfstate`).
  The bucket is versioned (rollback on bad writes), AES256-encrypted at rest, has all four
  public-access-block flags set, and a bucket policy denying non-TLS access.
- **Locking:** native S3 lockfiles (`use_lockfile = true`, Terraform ≥ 1.10) — Terraform
  writes a lock object in the state bucket for the duration of a write. No DynamoDB table.
- **Bootstrap:** the backend infra cannot live in a config that *uses* it as a backend
  (chicken-and-egg), so it is provisioned by a standalone `bootstrap/` Terraform config
  that keeps its own local state and is applied once. **`bootstrap/` must be applied before
  any project's `terraform init`**, or `init` fails with `NoSuchBucket`.
- Each project gains a `backend.tf` with a `backend "s3"` block. Backend blocks cannot use
  variables/interpolation, so the bucket name is a hardcoded literal that must match the
  `bootstrap/` output.

## Alternatives Considered

**Keep local state, copy `terraform.tfstate` between machines manually** — zero AWS cost,
no new infra. Rejected: error-prone, no locking, and the exact manual step that was missed
to cause ERR-001. It treats the symptom, not the cause.

**Commit state to git** — makes state travel with config. Rejected outright: state can
contain plaintext secrets, so committing it is a credential-exposure risk; it also offers
no locking and produces constant merge conflicts on `serial`.

**Terraform Cloud / HCP remote backend** — managed state, locking, and run history with no
self-managed infra. Rejected for a personal portfolio project: introduces an external SaaS
dependency and account, where a self-managed S3 bucket in the same AWS account is simpler
and free-tier-friendly.

**S3 backend with a DynamoDB lock table** — the long-established locking pattern and the
initial choice here. Rejected: Terraform 1.15.4 **deprecates** the `dynamodb_table` backend
parameter in favor of `use_lockfile`, and a separate table is extra infra to provision,
name, and pay for. Native lockfiles give equivalent locking with one fewer resource and no
deprecation warning, so DynamoDB was dropped before any of it was deployed.

## Consequences

- The `*AlreadyExists` / orphan-on-apply class of failure is structurally eliminated — any
  machine with the committed `backend.tf` reads the same state.
- Concurrent applies are blocked by the S3 lockfile instead of silently corrupting state.
- A one-time `bootstrap/` apply is now a prerequisite before any project can `init`. New
  contributors must run it (or have it already exist) before `terraform init` — skipping it
  fails `init` with `NoSuchBucket` (safe: state is left unmodified). See `bootstrap/README.md`.
- `backend.tf` names are hardcoded; renaming the bucket is a coordinated change across
  `bootstrap/` and every project's `backend.tf`.
- Migrating an existing project is `terraform init` (Terraform offers to copy local state
  to S3). For P4 specifically the local state is empty post-destroy, so the migration is a
  clean re-apply rather than a state copy.
- Minor per-apply latency from S3 round-trips on lock acquire/release; negligible.
- Bootstrap state itself remains local — an accepted, bounded chicken-and-egg, since it
  changes rarely and holds no application secrets.

## Related

- ERR-001 — local state not shared across machines (the failure this decision resolves)
- CHANGELOG: `docs/changelog/26-06-06 [upgrade] P4 S3 Remote Backend and Bootstrap.md`
- ADR 0001 — SSM Parameter Store for API credentials (the `/cloud-portfolio/` shared-
  namespace pattern this ADR mirrors for the `cloud-portfolio-tfstate-*` bucket)
