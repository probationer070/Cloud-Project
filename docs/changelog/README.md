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
