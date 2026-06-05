[thinking]

# Deploy All Projects at Once — Alternatives to tf-all.ps1

**Date:** 2026-06-02
**Context:** Currently tf-all.ps1 runs terraform init/plan/apply/destroy on P1–P4 sequentially in PowerShell. This doc explores what other approaches exist, for both learning and portfolio purposes.
**Constraint:** No Terragrunt.

---

## Approach A — Enhance tf-all.ps1 with PowerShell Parallel Jobs

Add a `-Parallel` switch to the existing script. `Start-Job` or `ForEach-Object -Parallel` (PowerShell 7+) runs all 4 `terraform apply` processes at the same time.

**Usage:**
```powershell
.\tf-all.ps1 apply -Parallel
```

**Trade-offs:**
- Pro: zero new installs, extends what already exists, stays in PowerShell
- Con: output from 4 projects interleaves in the terminal (hard to read); requires PowerShell 7+

---

## Approach B — Taskfile (go-task)

Install `go-task` (single binary). Define a `Taskfile.yml` in the repo root with a `deploy:all` task that runs all 4 projects in parallel.

**Install:**
```powershell
winget install Task.Task
```

**Usage:**
```powershell
task deploy   # deploys all 4 projects in parallel
task plan     # plans all 4 projects in parallel
```

**Taskfile.yml structure:**
```yaml
version: '3'
tasks:
  deploy:
    desc: Deploy all projects in parallel
    deps: [deploy:p1, deploy:p2, deploy:p3, deploy:p4]

  deploy:p1:
    dir: project1-static-web
    cmds:
      - terraform init -input=false
      - terraform apply -input=false -auto-approve

  deploy:p2:
    dir: project2-serverless-pipeline
    cmds:
      - terraform init -input=false
      - terraform apply -input=false -auto-approve

  deploy:p3:
    dir: project3-smart-vault
    cmds:
      - terraform init -input=false
      - terraform apply -input=false -auto-approve

  deploy:p4:
    dir: project4-ai-chatbot
    cmds:
      - terraform init -input=false
      - terraform apply -input=false -auto-approve
```

**Trade-offs:**
- Pro: clean YAML, built-in parallel + dependency graph, cross-platform, shows modern tooling knowledge
- Con: one new tool to install; another config file to maintain

---

## Approach C — GitHub Actions Matrix with terraform apply (Recommended)

Extend the existing `.github/workflows/terraform-init.yml` to run real plan/apply using a matrix strategy. All 4 projects run in parallel on separate GitHub-hosted runners.

**Trigger flow:**
- Pull Request → `terraform plan` (output posted as PR comment)
- Merge to main → `terraform apply` (with manual approval gate via GitHub Environment)

**Matrix strategy example:**
```yaml
strategy:
  matrix:
    project: [project1-static-web, project2-serverless-pipeline, project3-smart-vault, project4-ai-chatbot]
```

**Requirements:**
- AWS credentials stored in GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- GitHub Environment named `production` with required reviewer (approval gate before apply)

**Trade-offs:**
- Pro: fully automated cloud-triggered deployment, strongest CI/CD portfolio signal, no local command needed
- Con: AWS credentials must be stored in GitHub Secrets; needs manual approval gate to be safe

---

## Bonus — AWS CodePipeline + CodeBuild (Most AWS-Native)

Build a CodePipeline in Terraform itself. On git push, CodePipeline triggers CodeBuild to run terraform for each project. Entirely inside AWS.

**Architecture:**
```
GitHub push
    │
    ▼
CodePipeline (Source stage)
    │
    ▼
CodeBuild (Build stage) ── runs terraform plan/apply
    │
    ▼
SNS notification (success/failure)
```

**Trade-offs:**
- Pro: pure AWS, highest interview value for "AWS DevOps" roles, no GitHub Actions dependency
- Con: significant extra Terraform code (~P5 scope), CodeBuild minutes have cost, complex to debug

---

## Recommendation

**Implement Approach C** — GitHub Actions matrix with `terraform plan` on PRs and `terraform apply` on merge. This directly fixes the biggest gap in the current portfolio (CI/CD only runs `terraform init`).

**Add Approach B as a local complement** — `task deploy` gives a single-command local deploy experience that's cleaner than tf-all.ps1 for day-to-day use.

**Skip Approach A** — the interleaved output makes it worse UX than the current sequential script.

**Save CodePipeline for a future P5 project** — it deserves its own project, not a bolt-on.
