# 26-06-11 [bug] P5 uv Not Found Replaced with pip

**Type:** bug
**Branch / Commit:** Testo / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project5-document-engine/main.tf` | `terraform_data.install_ingest_deps` | Replaced `uv pip install` with `python -m pip install` |

## Why Changed

`terraform apply` failed on Windows with `'uv' is not recognized as an internal or external command`. The `local-exec` provisioner called `uv pip install` but `uv` is not a standard tool — it must be installed separately. `python -m pip` achieves the same result using only the Python runtime already on PATH.

## Contents Diff

**`project5-document-engine/main.tf` — `terraform_data.install_ingest_deps`**
```hcl
# Before
command = "uv pip install -r ${path.module}/lambda/ingest/requirements.txt --target ${path.module}/lambda/ingest --quiet"

# After
command = "python -m pip install -r ${path.module}/lambda/ingest/requirements.txt --target ${path.module}/lambda/ingest --quiet"
```

## Improvements

`terraform apply` no longer fails on machines without `uv` installed. Python 3 ships with `pip` as a standard module, making the provisioner portable across Windows environments.

## Performance Impact

none

## Agents Consulted

none

## Findings Addressed

none

## Findings Deferred

The open plan `docs/plan/26-06-10 P5 Container Lambda ECR Switch.md` replaces this provisioner entirely with Docker/ECR. This fix is a stopgap for zip-based deployment.
