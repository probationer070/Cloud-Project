# ERR-NNN — Short Title

> Copy this file to `ERR-NNN-short-description.md`. Fill every field. Add index row to README.md.

---

## Summary

One or two sentences. What went wrong, where, and what the visible symptom was.

---

## Metadata

| Field | Value |
|-------|-------|
| **ID** | ERR-NNN |
| **Date Discovered** | YYYY-MM-DD |
| **Date Resolved** | YYYY-MM-DD |
| **Severity** | `prod-impact` / `dev-only` / `silent-failure` / `test-catch` |
| **Component** | e.g. `lambda/cleanup/runner.py`, `main.tf`, `lambda/restore/index.py` |
| **Introduced In** | Commit hash or branch name (if known) |
| **Discovered By** | `agent-review` / `manual-test` / `prod-alert` / `code-review` / `test-failure` |

---

## Symptom

What the developer or user observed. Be concrete — error message, wrong output,
unexpected behavior, silent wrong result.

```
<paste actual error message, log output, or describe observed behavior>
```

---

## Root Cause

The underlying reason the bug existed. Go one level deeper than "the code was wrong."

Examples of good root cause statements:
- "Conditional hierarchy collapsed during refactor — admin check was gated inside premium check but flattening removed the gate"
- "Constraint scope expanded — regional validator extracted to shared function without preserving the EU exclusion"
- "Broad `except Exception:` silenced a `KeyError` from missing env var, returning wrong default silently"
- "Pagination not used — `describe_snapshots()` returned first 1000 only, rest silently skipped"

---

## Fix Applied

### Files Changed

| File | Change |
|------|--------|
| `path/to/file.py` | Describe what changed |

### Code Change Summary

Brief description of what was modified and why that fixes the root cause.
If the diff is small, paste it here. If large, reference the commit hash.

```python
# Before
...

# After
...
```

---

## Prevention

### What to Check in Future

Specific, actionable checks — written so an agent or reviewer can run them mechanically.

- [ ] Check X whenever doing Y
- [ ] Verify Z when extracting shared validators
- [ ] Add test for edge case W before refactoring related logic

### Agent / Checklist Update

Did this error reveal a gap in an existing agent checklist?

| Agent File | Change Made | Rationale |
|-----------|-------------|-----------|
| `.agents/code-reviewer.md` | Added check for X | This error would have been caught |
| `.agents/refactoring.md` | Added WARN for Y pattern | Root cause pattern not previously covered |

If no agent update was warranted, write "N/A — existing checklist covers this pattern."

### Test Added

What test was added or updated to catch this regression?

```python
def test_<description>():
    # reproduces the original failure
    ...
```

If no test was added, explain why (e.g., "integration-only behavior, covered by golden master").

---

## Related

- **Related errors:** (link to other ERR-NNN files if same pattern)
- **Agent findings:** (BLOCK/WARN finding ID that flagged or should have flagged this)
- **CHANGELOG entry:** (date of the fix entry in `docs/CHANGELOG.md`)
