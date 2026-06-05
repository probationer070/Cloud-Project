---
Type: upgrade
Files Changed:
  - README.md — intro paragraph, P4 section "P1~P3 재사용 패턴", P4 design doc link added
  - project4-ai-chatbot/README.md — full rewrite: fixed stale Step 2 (gemini_api_key removed from variables.tf), added SSM put-parameter step, added project independence note, added expected outputs and response examples
  - docs/design/p4-ai-chatbot/design.md — new file: P4 architecture, resource inventory, Lambda 5-step flow, security notes, cost table, deployment sequence, pattern reuse table
  - docs/design/p1-static-web/design.md — "How P4 reuses this" section: added independence callout
  - docs/design/p2-serverless-pipeline/design.md — "How P4 reuses this" section: added independence callout
  - docs/design/p3-smart-vault/design.md — "How P4 reuses this" section: added independence callout
Why Changed: (1) README and design docs implied P4 reuses P1–P3 infrastructure, which reads as a deployment prerequisite. P4's main.tf has zero remote state or data source references to P1/P2/P3 — it creates everything independently. (2) P4 README Step 2 referenced gemini_api_key in variables.tf, which was removed in the SSM migration (26-06-02 changelog). The README was giving wrong instructions for the actual deployment flow. (3) P4 had no design doc while P1/P2/P3 each had one, leaving the architecture undocumented.
Contents Diff: |
  project4-ai-chatbot/README.md Step 2 before:
    gemini_api_key = "AIzaSy..."   # ← Gemini API 키 입력

  project4-ai-chatbot/README.md Step 2 after:
    Removed — replaced with SSM put-parameter command (Step 2) and note
    that gemini_api_key does not exist in variables.tf
Improvements:
  - P4 README now matches the actual deployment flow (SSM-first)
  - All projects clarified as fully independent — no deployment ordering confusion
  - P4 now has a design doc consistent with P1/P2/P3
Performance Impact: none
Agents Consulted: none
Findings Addressed: none
Findings Deferred: none
