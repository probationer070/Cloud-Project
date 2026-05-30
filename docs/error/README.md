# Error Record Index — Smart Vault

Every bug that reaches a running system (local, dev, or prod) gets a record here.
The goal is not blame — it is **preventing the same class of bug from recurring**.

Records are written after the fix is confirmed. They answer three questions:
1. What happened and why?
2. How was it fixed?
3. What prevents it from happening again?

---

## How to Create a Record

1. Copy `template.md` to a new file named `ERR-NNN-short-description.md`
   - Increment `NNN` from the last entry in the index below
   - Keep the short description to 3–5 words, kebab-cased
2. Fill in all fields — leave none blank (write "N/A" only if genuinely not applicable)
3. Add a one-line entry to the index table below
4. Add a CHANGELOG entry in `docs/CHANGELOG.md`

**When to write a record:**
- A bug caused incorrect behavior in any environment (local, dev, or prod)
- A silent failure was discovered (wrong output, wrong data, no error raised)
- A test caught a regression introduced by a code change
- An agent finding (BLOCK/WARN) revealed an existing defect in running code

**When NOT to write a record:**
- Type errors or syntax errors caught before any execution
- Failing tests that were never passing (expected failures during development)
- Configuration mistakes with no code change required

---

## Error Index

| ID | Date | Component | Summary | Status |
|----|------|-----------|---------|--------|
| — | — | — | No errors recorded yet | — |
