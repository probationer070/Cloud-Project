# 26-06-05 [upgrade] Gemma 4 Model and History Sort Fix

**Type:** upgrade
**Branch / Commit:** Testo / pending

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project4-ai-chatbot/lambda/chatbot/index.py` | `save_history` | Timestamp suffixes changed from `_user`/`_assistant` to `_0`/`_1` |
| `project4-ai-chatbot/variables.tf` | `gemini_model` variable | Default changed from `gemini-2.0-flash` to `gemma-4-26b-a4b-it` |
| `project4-ai-chatbot/README.md` | `## Test Scenarios` | Added model note; strengthened Test 2 to verify history bug fix |

## Why Changed

Two problems reported: (1) chatbot returns the same response repeatedly; (2) user wants to switch from `gemini-2.0-flash` to Gemma 4 26B (`gemma-4-26b-a4b-it`), which has a 1,500 RPD free-tier limit via the Gemini API.

Root cause of the repeated-response bug: `save_history()` stored user and assistant messages with ISO timestamp suffixes `_user` and `_assistant`. Because `_assistant < _user` alphabetically (`a < u`), DynamoDB's ascending sort returned the assistant message before the user message in every turn. The `get_history()` pairing loop at line 227 expects `user` first, so every pair was skipped and history returned empty. On the 3rd+ call the loop began mismatching turns — feeding turn-N's user message against turn-(N+1)'s assistant response — producing corrupt context and repeated outputs.

## Contents Diff

**`lambda/chatbot/index.py` — `save_history`**
```python
# Before
"timestamp": now.isoformat() + "_user"
"timestamp": now.isoformat() + "_assistant"

# After
"timestamp": now.isoformat() + "_0"   # sorts before _1
"timestamp": now.isoformat() + "_1"
```

**`variables.tf` — `gemini_model`**
```hcl
# Before
default = "gemini-2.0-flash"

# After
default = "gemma-4-26b-a4b-it"
```

## Improvements

- Conversation history now sorts reliably: user message always precedes its paired assistant message regardless of how fast the Lambda runs.
- Model switched to Gemma 4 26B — fits within the 1.5k RPD free tier.
- Test Scenario 2 in README explicitly describes what to observe to confirm the history bug is fixed.

## Performance Impact

No latency change. DynamoDB schema unchanged (timestamp remains type S). Existing `_user`/`_assistant` items expire via 24h TTL with no manual cleanup needed.

## Agents Consulted

security, idea-management

## Findings Addressed

none

## Findings Deferred

none
