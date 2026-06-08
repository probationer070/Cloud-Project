# Change Log Index — Smart Vault

Each change has its own file. Filename format: `YY-MM-DD [type] Subject.md`
Types: `test` · `upgrade` · `bug`

Use `docs/changelog/template.md` to create new entries.

---

| Date | Type | Subject | Files Touched |
|------|------|---------|---------------|
| 26-05-30 | bug | [Terraform S3 Replication and Lambda Concurrency Errors](26-05-30%20[bug]%20Terraform%20S3%20Replication%20and%20Lambda%20Concurrency%20Errors.md) | `main.tf` |
| 26-05-30 | bug | [EC2 Free Tier Instance Type Seoul Region](26-05-30%20[bug]%20EC2%20Free%20Tier%20Instance%20Type%20Seoul%20Region.md) | `main.tf` |
| 26-05-30 | upgrade | [API Gateway REST API with Native Key Auth](26-05-30%20[upgrade]%20API%20Gateway%20REST%20API%20with%20Native%20Key%20Auth.md) | `main.tf`, `lambda/restore/index.py`, `variables.tf`, `terraform.tfvars`, `outputs.tf` |
| 26-05-31 | upgrade | [P4 Chatbot Security and Latency Hardening](26-05-31%20[upgrade]%20P4%20Chatbot%20Security%20and%20Latency%20Hardening.md) | `p4/lambda/chatbot/index.py`, `p4/main.tf`, `p4/iam.tf`, `p3/iam.tf` |
| 26-05-31 | upgrade | [Repository Documentation and Agent Overhaul](26-05-31%20[upgrade]%20Repository%20Documentation%20and%20Agent%20Overhaul.md) | `.agents/`, `README.md`, `.claude/CLAUDE.md`, `docs/design/`, `docs/todo.md` |
| 26-05-31 | bug | [API Gateway Access Log Format Attribute Missing](26-05-31%20[bug]%20API%20Gateway%20Access%20Log%20Format%20Attribute%20Missing.md) | `p4/main.tf` |
| 26-05-31 | upgrade | [Root README Expanded with Service Detail](26-05-31%20[upgrade]%20Root%20README%20Expanded%20with%20Service%20Detail.md) | `README.md` |
| 26-05-31 | upgrade | [One Command Terraform Init All Projects](26-05-31%20[upgrade]%20One%20Command%20Terraform%20Init%20All%20Projects.md) | `init-all.ps1`, `init-all.sh`, `.github/workflows/terraform-init.yml`, `.gitignore` |
| 26-05-31 | bug | [Project3 Dead VPC Data Sources Blocking Plan](26-05-31%20[bug]%20Project3%20Dead%20VPC%20Data%20Sources%20Blocking%20Plan.md) | `project3-smart-vault/main.tf` |
| 26-05-31 | upgrade | [Terraform Lifecycle Wrapper tf-all.ps1](26-05-31%20[upgrade]%20Terraform%20Lifecycle%20Wrapper%20tf-all.ps1.md) | `tf-all.ps1` |
| 26-05-31 | bug | [Project3 EC2 No Default VPC subnet_id Missing](26-05-31%20[bug]%20Project3%20EC2%20No%20Default%20VPC%20subnet_id%20Missing.md) | `project3-smart-vault/main.tf` |
| 26-06-02 | upgrade | [P4 Gemini API Key Moved to SSM Parameter Store](26-06-02%20[upgrade]%20P4%20Gemini%20API%20Key%20Moved%20to%20SSM%20Parameter%20Store.md) | `p4/variables.tf`, `p4/main.tf`, `p4/iam.tf`, `p4/lambda/chatbot/index.py` |
| 26-06-03 | upgrade | [Clarify Project Independence P1 P2 P3 Not Required for P4](26-06-03%20[upgrade]%20Clarify%20Project%20Independence%20P1%20P2%20P3%20Not%20Required%20for%20P4.md) | `README.md`, `project4-ai-chatbot/README.md`, `docs/design/p4-ai-chatbot/design.md` (new), `docs/design/p1~p3/design.md` |
| 26-06-04 | upgrade | [P1 P2 P3 Deploy and Test README](26-06-04%20[upgrade]%20P1%20P2%20P3%20Deploy%20and%20Test%20README.md) | `project1-static-web/README.md`, `project2-serverless-pipeline/README.md`, `project3-smart-vault/README.md` (new) |
| 26-06-05 | upgrade | [Gemma 4 Model and History Sort Fix](26-06-05%20[upgrade]%20Gemma%204%20Model%20and%20History%20Sort%20Fix.md) | `project4-ai-chatbot/lambda/chatbot/index.py`, `project4-ai-chatbot/variables.tf`, `project4-ai-chatbot/README.md` |
| 26-06-06 | upgrade | [Docs English Translation and Cross Platform Commands](26-06-06%20[upgrade]%20Docs%20English%20Translation%20and%20Cross%20Platform%20Commands.md) | `README.md`, `docs/todo.md`, `docs/design/*`, `docs/changelog/*` (KO snippets), `project1~4/README.md` |
| 26-06-06 | upgrade | [P4 S3 Remote Backend and Bootstrap](26-06-06%20[upgrade]%20P4%20S3%20Remote%20Backend%20and%20Bootstrap.md) | `bootstrap/*` (new), `project4-ai-chatbot/backend.tf` (new), `.agents/security.md`, `docs/error/ERR-001*` |
| 26-06-06 | upgrade | [Portfolio Technical Deep-Dive Document](26-06-06%20[upgrade]%20Portfolio%20Technical%20Deep-Dive%20Document.md) | `[project] portfolio only.md` (new) |
| 26-06-06 | bug | [P4 Full Teardown And Empty State Noop](26-06-06%20[bug]%20P4%20Full%20Teardown%20And%20Empty%20State%20Noop.md) | none (infra teardown — 11 P4 resource groups deleted via AWS CLI); see ERR-002 |
| 26-06-06 | upgrade | [P4 SSM Parameter Managed by Terraform](26-06-06%20[upgrade]%20P4%20SSM%20Parameter%20Managed%20by%20Terraform.md) | `project4-ai-chatbot/main.tf`, `README.md`, `file-structure.md`, `docs/adr/0001*`, `docs/design/p4*`, `[project] portfolio only.md` |
| 26-06-07 | upgrade | [Root README Synced With Current Code](26-06-07%20[upgrade]%20Root%20README%20Synced%20With%20Current%20Code.md) | `README.md` |
| 26-06-08 | upgrade | [GitHub Actions CI Pipeline with OIDC](26-06-08%20[upgrade]%20GitHub%20Actions%20CI%20Pipeline%20with%20OIDC.md) | `terraform-ci.yml`, `init-all.sh`, `README.md` |
| 26-06-08 | bug | [TF Plugin Cache Dir Fmt Check Failure](26-06-08%20[bug]%20TF%20Plugin%20Cache%20Dir%20Fmt%20Check%20Failure.md) | `terraform-ci.yml` |