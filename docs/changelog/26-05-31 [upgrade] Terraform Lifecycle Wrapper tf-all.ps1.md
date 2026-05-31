# 26-05-31 [upgrade] Terraform Lifecycle Wrapper tf-all.ps1

**Type:** upgrade
**Branch / Commit:** Testo / 4dc6529

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `tf-all.ps1` | — | New file: parameterized Terraform lifecycle wrapper for local dev |

## Why Changed

`init-all.ps1` only runs `terraform init`. Running `plan`, `apply`, or
`destroy` across all 4 projects required manually `cd`-ing into each directory
and typing the command individually. A single wrapper script was needed to:
- Run any Terraform command across all projects with one invocation
- Show a per-project result summary at the end (status, plan counts, error location)
- Guard `apply` and `destroy` against accidental multi-project execution

## Contents Diff

New file — no before state. Key design decisions:

**Command dispatch:**
```powershell
.\tf-all.ps1 plan           # plan all 4 projects
.\tf-all.ps1 apply p4       # apply only project4-ai-chatbot
.\tf-all.ps1 destroy p3     # destroy only project3-smart-vault
```

**Safety gate (apply / destroy on all):**
```powershell
if ($Command -in 'apply', 'destroy' -and $Project -eq '') {
    $answer = Read-Host "  This will $Command ALL projects. Type 'yes' to continue"
    if ($answer -ne 'yes') { exit 1 }
}
```

**Per-project output capture + real-time display:**
```powershell
& terraform $Command -input=false 2>&1 | ForEach-Object {
    Write-Host $line        # real-time display
    $capturedLines.Add($line) # stored for parsing
}
```

**Summary table (at end):**
```
------------------------------------------------------------------------
  PLAN SUMMARY  —  4 project(s)
------------------------------------------------------------------------
  [OK]   project1-static-web          Plan: 22 to add, 0 to change, 0 to destroy
  [ERR]  project2-serverless-pipeline Error: no matching EC2 VPC found (main.tf:577)
  [OK]   project3-smart-vault         Plan: 8 to add, 0 to change, 0 to destroy
  [OK]   project4-ai-chatbot          Plan: 15 to add, 0 to change, 0 to destroy
------------------------------------------------------------------------
  Total: 4  |  OK: 3  |  ERROR: 1
------------------------------------------------------------------------
```

## Improvements

- Single command replaces manual `cd` + `terraform <cmd>` per project
- `[OK]` / `[ERR]` / `[WARN]` summary with plan counts and error file:line
- Project filtering: `p4` matches `project4-ai-chatbot`
- Safety confirmation gate for `apply` and `destroy` on all projects
- Exit code 1 if any project errored (CI-compatible)
- ASCII-only status indicators (no emoji) for Windows PowerShell 5.1 encoding compatibility

## Performance Impact

- Developer time: replaces ~4 manual `cd + terraform plan` cycles with one command
- No AWS API overhead change — same terraform calls, different wrapper

## Agents Consulted

security, refactoring

## Findings Addressed

- [WARN] No safety gate on `apply-all` — addressed with explicit `yes` confirmation prompt
- [WARN] No visibility into per-project results after multi-project run — addressed with summary table

## Findings Deferred

- `tf-all.ps1` is a temporary bridge — Phase 2 (Terragrunt) replaces it with
  `terragrunt run-all plan` etc. See design doc `VIP-Testo-design-20260531-215813.md`.
- No bash equivalent (`tf-all.sh`) written yet — CI still uses `init-all.sh`.
  Will be superseded by Terragrunt before a bash version is needed.
