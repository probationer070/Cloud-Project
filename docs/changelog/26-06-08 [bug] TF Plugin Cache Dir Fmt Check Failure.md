# 26-06-08 [bug] TF Plugin Cache Dir Fmt Check Failure

**Type:** bug
**Branch / Commit:** Testo / 8c0d549

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `.github/workflows/terraform-ci.yml` | `fmt-check` job, `validate` job, `plan` job | Moved `TF_PLUGIN_CACHE_DIR` from workflow-level `env:` to per-job `env:` on `validate` and `plan` only |

## Why Changed

The `fmt-check` job failed immediately on every run with:

```
Error: The specified plugin cache dir .../.terraform.d/plugin-cache cannot be opened:
stat ...: no such file or directory
```

Root cause: `TF_PLUGIN_CACHE_DIR` was declared at the workflow level, so all three jobs
inherited it. Terraform reads this env var on startup and errors if the directory does not
exist. The `validate` and `plan` jobs create the directory in a setup step — `fmt-check`
does not, because `terraform fmt` never downloads providers and has no need for a cache dir.

## Contents Diff

**`.github/workflows/terraform-ci.yml`**

```yaml
# Before — TF_PLUGIN_CACHE_DIR at workflow level (all jobs inherit it)
permissions:
  id-token: write
  contents: read

env:
  TF_PLUGIN_CACHE_DIR: ${{ github.workspace }}/.terraform.d/plugin-cache

jobs:
  fmt-check:
    runs-on: ubuntu-latest
    ...

  validate:
    needs: fmt-check
    runs-on: ubuntu-latest
    steps:
      ...

  plan:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      ...

# After — TF_PLUGIN_CACHE_DIR scoped to validate and plan jobs only
permissions:
  id-token: write
  contents: read

jobs:
  fmt-check:
    runs-on: ubuntu-latest      # no env: block — fmt never needs the cache dir
    ...

  validate:
    needs: fmt-check
    runs-on: ubuntu-latest
    env:
      TF_PLUGIN_CACHE_DIR: ${{ github.workspace }}/.terraform.d/plugin-cache
    steps:
      ...

  plan:
    needs: validate
    runs-on: ubuntu-latest
    env:
      TF_PLUGIN_CACHE_DIR: ${{ github.workspace }}/.terraform.d/plugin-cache
    steps:
      ...
```

## Improvements

`fmt-check` job no longer errors on startup — `terraform fmt` runs cleanly without needing a provider cache directory.

## Performance Impact

none — 4 lines changed, no runtime impact.

## Agents Consulted

`/cicd`

## Findings Addressed

none (bug discovered from live CI run)

## Findings Deferred

none
