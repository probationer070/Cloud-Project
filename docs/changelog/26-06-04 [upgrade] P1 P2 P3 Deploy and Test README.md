---
Type: upgrade
Files Changed:
  - project1-static-web/README.md — full rewrite: sequential deploy steps, SNS confirmation note, test scenarios (HTTPS, redirect, S3 403, dashboard), checklist, destroy
  - project2-serverless-pipeline/README.md — full rewrite: sequential deploy steps, SNS confirmation note, test scenarios (CSV→DynamoDB, JSON, quarantine, PDF/Textract, API GW, dashboard), checklist, destroy
  - project3-smart-vault/README.md — new file (did not exist): EC2 prerequisite note, sequential deploy steps, SNS confirmation note, test scenarios (manual backup, snapshot check, cleanup dry-run, archive log, DR replication, restore API, dashboard), checklist, destroy
Why Changed: P1 and P2 READMEs were missing the format consistency established by the updated P4 README — no independence note, no clear separation of deploy vs test, no expected outputs, no step-by-step test scenarios. P3 had no README at all (its content was buried inside the design doc). A new developer would not know how to deploy and test these projects end-to-end without reading multiple files.
Contents Diff: |
  All three now follow the same structure as project4-ai-chatbot/README.md:
    - Independence callout at top
    - Architecture diagram
    - Cost table
    - Step-by-step deploy sequence with terraform output values
    - Numbered test scenarios with expected output
    - Validation checklist
    - Common errors section
    - Destroy instructions with pre-destroy steps
Improvements:
  - P3 README created from scratch — was previously undocumented
  - SNS subscription confirmation step explicitly called out in all three
  - P3 calls out EC2 prerequisite (without backup:true tag, Backup Lambda finds no targets)
  - P3 restore API test uses `terraform output -raw restore_api_key_value` (sensitive value handling)
  - All destroy sections list pre-destroy S3 bucket emptying commands
Performance Impact: none
Agents Consulted: none
Findings Addressed: none
Findings Deferred: none
