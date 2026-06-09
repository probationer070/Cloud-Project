# 26-06-10 [upgrade] P5 Docker vs Zip Packaging Clarification

**Type:** upgrade
**Branch / Commit:** Testo / HEAD

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project5-document-engine/README.md` | — | Added "Lambda Packaging" section explaining zip deployment and Dockerfile status |

## Why Changed

A review of the deployment found that `lambda/ingest/Dockerfile` and `lambda/query/Dockerfile` exist but are not referenced by Terraform. Both Lambdas are deployed as zip packages via `archive_file` + local `uv pip install`. Without documentation, the Dockerfiles are misleading — a future reader could assume container image deployment is in use when it is not.

## Contents Diff

New section added to README between "File Structure" and "Deployment Steps". No code changed.

## Improvements

- Makes the packaging method unambiguous: zip, not container image
- Documents what the Dockerfiles are for (future ECR/container image path) so they are not deleted as dead files
- Explains the local `uv pip install` → zip flow that `terraform apply` runs automatically

## Performance Impact

none

## Agents Consulted

none

## Findings Addressed

none

## Findings Deferred

none
