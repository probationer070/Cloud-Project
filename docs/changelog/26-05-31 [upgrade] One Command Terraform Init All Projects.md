# 26-05-31 [upgrade] One Command Terraform Init All Projects

**Type:** upgrade
**Branch / Commit:** Testo / 4dc6529

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `init-all.ps1` | — | New file: PowerShell wrapper to init all 4 Terraform projects with one command |
| `init-all.sh` | — | New file: Bash equivalent for CI and WSL |
| `.github/workflows/terraform-init.yml` | — | New file: GitHub Actions workflow calling `init-all.sh` on push |
| `.gitignore` | — | Commented out `.terraform.lock.hcl` exclusion so lock files can be committed |

## Why Changed

Running `terraform init` on this repo required manually `cd`-ing into each of 4 project
directories (project1-static-web, project2-serverless-pipeline, project3-smart-vault,
project4-ai-chatbot) and running the command individually. There is no native Terraform
command to init multiple root modules at once.

Additionally, `.terraform.lock.hcl` was excluded by `.gitignore`, meaning CI could silently
pull different provider versions than what was tested locally.

Trigger: engineering review (plan-eng-review) and design session (office-hours) on 2026-05-31
identified both issues before any implementation.

## Contents Diff

New files — no before state. Key logic decisions documented below.

**`init-all.ps1` — loop design**
```powershell
# Resolves paths relative to script location, not cwd
$scriptDir = $PSScriptRoot

# Filters project* dirs to only those containing main.tf
$projects = Get-ChildItem -Path $scriptDir -Directory -Filter 'project*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'main.tf') }

# Guards against zero matches (would otherwise silently succeed)
if ($projects.Count -eq 0) {
    Write-Error "No Terraform projects found under $scriptDir"
    exit 1
}
```

**`.gitignore` — lock file exclusion**
```
# Before
.terraform.lock.hcl

# After
# .terraform.lock.hcl
```

## Improvements

- `./init-all.ps1` or `bash init-all.sh` from the repo root initializes all 4 projects
- Scripts work from any directory (script-relative paths via `$PSScriptRoot` / `$(dirname "$0")`)
- Only directories containing `main.tf` are passed to `terraform init` — non-Terraform dirs are skipped
- Zero-project guard: explicit `exit 1` with a clear message if no Terraform dirs are found
- CI workflow (`terraform-init.yml`) runs on push to `main` and `Testo` branches
- Provider plugin caching (`TF_PLUGIN_CACHE_DIR` + `actions/cache`) avoids re-downloading the
  AWS provider (~50MB) on every CI run — cache busts automatically when lock files change
- `.terraform.lock.hcl` files are now trackable by git, ensuring CI and local use identical
  provider versions (HashiCorp recommendation)

## Performance Impact

- CI: provider download drops from ~200MB per run to ~0MB after first cache hit (4 projects × ~50MB AWS provider)
- Local: no change — `terraform init` still runs sequentially across 4 dirs (~10–30s total depending on network)
- Line count: +42 lines across 3 new files

## Agents Consulted

security, idea-management

## Findings Addressed

- [WARN] `.terraform.lock.hcl` gitignored — CI could silently use different provider versions
  than local. Fixed by commenting out the exclusion in `.gitignore`.
- [WARN] Scripts assumed current working directory was repo root — fixed with script-relative
  path resolution.
- [WARN] `project*` glob matched non-Terraform directories — fixed with `main.tf` presence filter.
- [WARN] Zero-project match would exit 0 silently — fixed with explicit guard.

## Findings Deferred

- Phase 2 (Terragrunt): `terragrunt run-all init` on a separate branch will replace both scripts.
  Requires migrating all 4 projects to remote S3 backend first (local state is a blocker for
  `run-all apply`). Inline `provider "aws"` blocks in each `main.tf` must be audited against
  Terragrunt `generate` blocks before migration.
- Open question: whether CI needs `-backend-config` passthrough flags for remote backend setup.
