# Refactoring Review

Run after writing or expanding a function to catch complexity, hidden failures,
and duplication before they compound.

## How to use

Type `/refactoring` after modifying or creating any function, especially in `lambda/*/index.py`.

## Steps

1. Read the changed function(s) from the current diff.
2. Run the checklist below against each changed function.
3. Report findings using the output format.

## Checklist

### Size and complexity
- [ ] Lambda handler ≤ 40 lines — if longer, flag sections that should be extracted to helpers
- [ ] Nesting depth ≤ 4 levels — if deeper, identify guard-clause opportunities (early returns for error cases)
- [ ] No function doing more than one thing — the function name describes exactly what it does

### Error handling
- [ ] No bare `except:` or `except Exception as e: pass` — errors must surface or be logged and re-raised
- [ ] No silent swallowing of boto3 `ClientError` — at minimum log the error code and re-raise

### Duplication
- [ ] Same logic (DynamoDB write, SSM fetch, chunk splitting) does not appear in 3+ Lambda packages
- [ ] If a shared module is warranted: it has no AWS-service-specific dependency (pure logic only)

### Conditional logic safety
- [ ] When flattening nested `if` blocks with guard clauses, verify happy path and all branch outcomes
  are identical before and after
- [ ] Business rule ordering (e.g., check escalation before abuse) preserved after any restructuring

## Output format

```
## /refactoring — YYYY-MM-DD

### Findings
[ACTION]   lambda/chatbot/index.py:12-67 — handler is 55 lines; extract Gemini call to call_ai_provider()
[DEFER]    lambda/ingest/index.py:34 — chunk-split logic duplicated in query/index.py but only 2 packages;
           flag again if a third package adds it
[RESOLVED] lambda/query/index.py:18 — broad except replaced with specific ClientError handling

### Summary
1 ACTION to address now, 1 DEFER recorded, 1 already resolved.

### Next step
Extract lines 23-45 of lambda/chatbot/index.py into a call_ai_provider(prompt, history) helper function.
```

If no findings: write `No findings — all checks pass.` under Findings.
