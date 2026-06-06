# 26-06-06 [upgrade] Docs English Translation and Cross Platform Commands

**Type:** upgrade
**Branch / Commit:** dev-bash / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `README.md` | whole document | Translated Korean → English (intro, all P1–P4 sections, tables, ASCII diagrams, repo tree, workflow). Kept `정리자료/` directory name (real, untracked, marked do-not-modify) |
| `docs/todo.md` | whole document | Translated Korean → English (P4 build plan) |
| `docs/design/p1-static-web/design.md` | title, "How P4 reuses this" | Translated title parenthetical + independence note |
| `docs/design/p2-serverless-pipeline/design.md` | title, "How P4 reuses this" | Translated title parenthetical + independence note |
| `docs/design/p3-smart-vault/design.md` | preserved-README section | Translated full Korean lower half (architecture, file layout, cost, deploy/test steps, checklist) |
| `docs/design/p4-ai-chatbot/design.md` | whole document | Translated Korean throughout (purpose, diagram, tables, history design, security, cost, provider switching, deploy summary) |
| `docs/changelog/26-05-30 [upgrade] API Gateway REST API with Native Key Auth.md` | Why Changed, Contents Diff | Translated Korean log-message literal + code comments |
| `docs/changelog/26-05-31 [bug] Project3 Dead VPC Data Sources Blocking Plan.md` | Contents Diff | Translated Korean code comment |
| `docs/changelog/26-06-02 [upgrade] P4 Gemini API Key Moved to SSM Parameter Store.md` | Contents Diff | Translated Korean variable description + error string |
| `docs/changelog/26-06-03 [upgrade] Clarify Project Independence ...md` | Files Changed, Contents Diff | Translated Korean section name + code comment |
| `project1-static-web/README.md` | Test 2, Test 4 | Added Linux `curl -I` variant + bash `aws cloudfront` continuation variant |
| `project2-serverless-pipeline/README.md` | Test 5 | Added bash `curl` + Windows `curl.exe` variants for the API upload |
| `project3-smart-vault/README.md` | Steps 1, Tests 1–3, Test 6 | Added bash variants for `aws`/`Get-Content`; added `curl`/`curl.exe` variants for restore |
| `project4-ai-chatbot/README.md` | Step 2, Tests 1–4 | Added bash variants for `aws ssm`/`aws dynamodb`; added `curl`/`curl.exe` variants for 4 chat tests |

## Why Changed

The repository documentation was authored in Korean (root `README.md`, `docs/todo.md`, design
docs) and its runnable commands were PowerShell-only (backtick continuation, `Invoke-RestMethod`,
`Get-Content`, `$VAR = terraform output`). A Linux/macOS reader — or a Windows user who prefers
real `curl` — could neither read the docs nor copy-paste the commands. The user requested a fully
English documentation set plus explicit Linux and `curl.exe` command variants in the READMEs.

## Contents Diff

**curl.exe JSON quoting (PowerShell 5.1 native-arg correctness)** — single-quoted JSON bodies are
mangled when handed to a native exe under Windows PowerShell (verified: `{"message": "..."}` →
`{message: How`). The `curl.exe` blocks therefore use backslash-escaped bodies, which round-trip
intact:
```powershell
# Wrong (mangled by PowerShell 5.1):
curl.exe ... -d '{"message": "How do I process a return?", "session_id": "test-001"}'

# Correct (delivered intact):
curl.exe ... -d '{\"message\": \"How do I process a return?\", \"session_id\": \"test-001\"}'
```
Linux/macOS `curl` blocks keep single-quoted bodies (correct for bash). Commands that are
byte-identical cross-platform (`terraform`, single-line `aws`, `git`) were left as a single block.

## Improvements

- Entire project documentation set is now English (only the real `정리자료/` directory name remains, by design)
- Every PowerShell-specific command in the 4 project READMEs now has a runnable Linux/macOS equivalent
- HTTP API tests have explicit `curl` (Linux/macOS) and `curl.exe` (Windows) variants, verified for correct JSON delivery
- All edited markdown files have balanced code fences (parity-checked)

## Performance Impact

none (documentation only)

## Agents Consulted

none — documentation-only change; no Terraform/IAM/Lambda/input surface per the `.agents` decision matrix

## Findings Addressed

none

## Findings Deferred

- [INFO] `docs/todo.md` §1 still states the Gemini key is stored in a Lambda environment variable,
  but it was moved to SSM Parameter Store (changelog `26-06-02`; confirmed by the P4 design doc and
  README). Translated faithfully rather than silently rewritten — flagged for a separate doc-sync fix.
