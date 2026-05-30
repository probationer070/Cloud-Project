# Refactoring Spaghetti Code — 7-Step Recovery Strategy

Spaghetti code is a symptom of accumulated business complexity, hidden assumptions,
temporal coupling, duplicated logic, and fear-driven maintenance. Effective refactoring
is not cosmetic cleanup — it is **recovering architectural clarity without destroying existing behavior**.

---

## Step 1 — Characterization Tests (Stabilize First)

Before changing any code, capture current behavior — even if that behavior looks wrong.

Characterization tests do NOT ask "what should the code do?" — they ask **"what does it currently do?"**

```python
def test_admin_premium_override():
    result = approve_order(user=admin_premium_user, order=sample_order)
    assert result == "approved"   # documents current behavior, not ideal behavior
```

Capture especially:
- Admin / premium / edge-currency / conflicting-flag combinations
- Invalid states and null values
- Weird production behavior — these encode hidden business assumptions

Refactoring without characterization tests is rewriting blindfolded.

---

## Step 2 — Flatten with Guard Clauses (Simplify Structure)

Reduce nesting aggressively. Deep nesting hides the happy path and creates invisible dependencies.

**Before:**
```python
if user:
    if user.active:
        if order:
            if order.total > 0:
                # actual logic buried here
```

**After (guard clauses):**
```python
if not user:          return rejected
if not user.active:   return rejected
if not order:         return rejected
if order.total <= 0:  return rejected
# happy path here — clearly visible
```

Guard clauses transform tree-shaped execution into linear flow.
Humans understand sequential flow far better than deeply nested branching.

---

## Step 3 — Let It Burn (Surface Unexpected Failures)

Do not hide unexpected failures behind broad exception handling.

**Anti-pattern:**
```python
try:
    process_order()
except:
    return "rejected"   # suppresses programming errors, broken assumptions, infra failures
```

**Better:**
```python
if amount is None:      # handle expected domain failure explicitly
    return rejected
# let unexpected failures surface — they are signals, not noise
```

"Let it burn" does not mean ignore errors. It means **do not suppress unknown failures blindly**.
Unexpected crashes expose broken assumptions and architectural flaws.
Suppressing them destroys observability.

---

## Step 4 — Name Complex Conditions (Expose Domain Meaning)

Extract multi-part logical expressions into named predicates.

**Before:**
```python
if (
    user.is_active
    and order.total > 100
    and not order.is_trial
    and (user.region == "EU" or user.is_premium)
):
```

**After:**
```python
if not is_eligible_order(user, order):
    return rejected
```

Named predicates:
- Expose domain meaning and business intent
- Create reusable domain concepts (`is_high_risk_customer()`, `requires_manual_review()`)
- Naturally evolve into specification objects or policy systems

---

## Step 5 — Use Pythonic Constructs (Declarative over Imperative)

Replace manual state tracking with Python built-ins that communicate intent directly.

**Before:**
```python
has_negative = False
for item in order.items:
    if item.price < 0:
        has_negative = True
```

**After:**
```python
if any(item.price < 0 for item in order.items):
    return rejected
```

Useful constructs: `any()`, `all()`, comprehensions, generators, `sum()`, `max()`, `min()`.

**Warning:** over-compression reduces readability. `any(a(b(c(x))) for x in y if z)`
may be harder to read than the explicit loop. Balance matters.

---

## Step 6 — Merge Duplicate Rules (Remove Duplication)

Repeated condition structures indicate a missing abstraction. Convert to rule lists.

**Before:**
```python
if not user.active:     return rejected
if order.has_discount:  return rejected
if order.total <= 0:    return rejected
```

**After:**
```python
rejection_rules = [
    lambda: not user.active,
    lambda: order.has_discount,
    lambda: order.total <= 0,
]
if any(rule() for rule in rejection_rules):
    return rejected
```

Rules become composable, reorderable, dynamically configurable, and independently testable.
This naturally evolves toward Specification Pattern, Rule Engines, or Validation Pipelines.

**Caution:** excessive lambda indirection can reduce readability — eventually explicit rule
dataclasses or named functions may be clearer than dense one-liners.

---

## Step 7 — Convert Stable Logic into Data (Data-Driven Design)

Stable branching rules belong in data structures, not procedural code.

**Before:**
```python
if region == "EU" and currency == "EUR":   ...
elif region == "US" and currency == "USD": ...
elif region == "JP" and currency == "JPY": ...
```

**After:**
```python
VALID_REGION_CURRENCY = {("EU", "EUR"), ("US", "USD"), ("JP", "JPY")}

if (region, currency) not in VALID_REGION_CURRENCY:
    return rejected
```

Data-driven logic:
- Centralizes configuration
- Enables extension without code changes
- Dramatically simplifies testing (one test per entry, not one per branch)
- Makes business policy configuration-driven rather than code-driven

Especially powerful for: permissions, feature flags, state transitions, regional rules, policy engines.

---

## The Five Phases (Summary)

| Phase | Technique | Goal |
|-------|-----------|------|
| 1 — Stabilize | Characterization tests | Protect existing behavior |
| 2 — Simplify | Guard clauses | Flatten control flow |
| 3 — Expose | Named predicates | Reveal domain semantics |
| 4 — Deduplicate | Rule lists | Centralize repeated logic |
| 5 — Externalize | Data structures | Make policy configurable |

---

## Incremental vs Big Rewrite

Large rewrites fail because hidden rules are forgotten, edge cases disappear,
and undocumented behavior changes silently.

**Safer path:** stabilize → simplify structure → extract concepts → remove duplication → convert to data.
Each step is independently verifiable. Characterization tests catch drift at every phase.

---

## Complexity Is Often Domain Complexity

Not all complexity is accidental. Finance, taxation, logistics, healthcare, permissions,
and international compliance are genuinely complicated domains.

The goal is not "eliminate all complexity" — it is **organize complexity into understandable structures**.

Spaghetti code is usually not caused by bad developers. It results from years of changing
requirements, emergency fixes, business pressure, and partial rewrites.
Refactoring is recovering architectural control over accumulated complexity, not blame assignment.
