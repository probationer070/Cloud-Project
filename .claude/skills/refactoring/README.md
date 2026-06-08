# /refactoring

**When to run:** After writing or expanding any function, especially Lambda handlers in `lambda/*/index.py`.

## What it checks

| Area | Rule |
|------|------|
| Size | Handler ≤ 40 lines — flag sections to extract |
| Nesting | ≤ 4 levels deep — flag for guard-clause flattening |
| Error handling | No bare `except:` or silent `ClientError` swallowing |
| Duplication | Same logic in 3+ Lambda packages → shared module candidate |
| Logic safety | Business rule ordering preserved when flattening conditionals |

## Output tags

| Tag | Meaning | Action required |
|-----|---------|-----------------|
| `[ACTION]` | Refactor now — complexity or hidden failure risk | Fix before moving on |
| `[DEFER]` | Worth noting but not urgent | Record in changelog; revisit when a third package duplicates |
| `[RESOLVED]` | Prior debt that was addressed | No action — confirms the fix |

## Example

```
/refactoring
```

```
## /refactoring — 26-06-08

### Findings
[ACTION]   lambda/chatbot/index.py:12-67 — handler is 55 lines; extract Gemini call to call_ai_provider()
[DEFER]    lambda/ingest/index.py:34 — chunk-split logic in 2 packages; flag again at 3

### Summary
1 ACTION to address now, 1 DEFER recorded.

### Next step
Extract lines 23-45 of lambda/chatbot/index.py into call_ai_provider(prompt, history).
```

## Tips

- A handler over 40 lines is almost always doing two things — the split point is usually obvious once flagged.
- `[DEFER]` findings accumulate. Search for them in changelogs before starting any new Lambda to see if a pattern has now hit 3 packages.
- Never flatten a nested `if` without first writing down the expected output for every branch — nesting encodes business rules.
