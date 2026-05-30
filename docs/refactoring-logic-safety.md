# Refactoring — Hidden Logic Coupling and the Illusion of Correct Tests

Refactoring is defined as "improving internal structure without changing external behavior."
In practice this is one of the hardest guarantees in software engineering.
The danger is not syntax errors — it is **preserving hidden business semantics** accidentally
encoded inside messy conditional logic.

---

## The Three Hidden Logic Error Patterns

### Pattern 1 — Conditional Hierarchy Collapse

**Before:** admin approval was gated inside a premium check. Admins approved *only when not premium*.

**After refactor:** the nesting was flattened. Admins became *always* approved.

The developer preserved individual conditions but destroyed the conditional hierarchy,
execution ordering, and contextual dependency between them.

**Key insight:** in imperative code, **structure itself carries meaning**.
Indentation, nesting order, and short-circuit evaluation encode domain rules implicitly.
Refactoring can preserve syntax while silently altering semantics.

---

### Pattern 2 — Constraint Scope Expansion

**Before:** negative-price validation applied only outside the EU region.

**After refactor:** the validation was extracted into a reusable function and called globally.
EU users were now incorrectly rejected.

This is **constraint scope expansion** — a locally scoped rule accidentally becomes universally enforced.

**Trigger:** extracting `validate_x(value)` without preserving the original execution context.

**Real-world sensitivity:** tax systems, compliance engines, permission systems, localization logic, payment workflows.
Regional and contextual rules are extremely sensitive to scope changes.

---

### Pattern 3 — Rule Collision via Flattening

**Before:** bulk non-trial purchases bypassed discount restrictions (asymmetric interaction).

**After refactor:** generalized "discount forbidden" validation blocked previously allowed cases.

This is **rule collision** — conditions that originally interacted asymmetrically were flattened
into a unified validation path, destroying the exception semantics.

**Root cause:** business logic is often non-linear, exception-driven, historically accumulated.
Naive simplification destroys edge semantics that have business value.

---

## The Illusion of Test Coverage

> High test coverage ≠ correctness.

Coverage measures **whether code executed** — not whether behavior was validated correctly.

A test may execute `if is_admin:` without verifying interaction with premium status,
region constraints, ordering semantics, or hidden edge conditions.
Coverage tools report success even when logic is wrong.

**Even 100% line coverage can miss:**
- Invalid assumptions about condition interaction
- Missing edge cases at the boundary of two rules
- Incorrect logic combinations across branches
- Semantic drift (behavior changed, test expectation was wrong to begin with)

```python
# This test passes at 100% coverage — but may be approving the wrong users
assert approve(user)  # checks "a result exists", not "the right users are approved"
```

Coverage is a **visibility metric**, not a correctness metric. It tells you which paths
were executed — it tells you nothing about whether those paths produce the right answer.

---

## Hidden Domain Knowledge Problem

Legacy systems contain undocumented business rules. The only source of truth is often:
- old code behavior,
- historical bugs,
- production logs,
- tribal team knowledge.

This makes refactoring fundamentally a **knowledge extraction process**, not just code cleanup.
The engineer must reverse-engineer implicit domain semantics from imperfect artifacts.

---

## Better Approaches

### Specification-Based Rule Design

Replace nested conditionals with first-class rule objects.

```python
# Instead of:
if is_admin and not is_premium:
    approve()
elif region != "EU" and price >= 0:
    approve()

# Prefer:
rules: list[Callable[[User], bool]] = [
    lambda u: u.is_admin and not u.is_premium,
    lambda u: u.region != "EU" and u.price >= 0,
]
approved = all(rule(user) for rule in rules)
```

Rules become: composable, independently testable, dynamically configurable, analyzable.
This evolves toward: Specification Pattern, Rule Engines, Policy Systems, Decision Graphs.

---

### Data Structures as Logic Compression

Replace giant condition trees with data-driven models.

```python
# Instead of:
if purchase_type == "bulk" and not is_trial:
    bypass_discount_check()

# Prefer:
DISCOUNT_BYPASS_CASES = {("bulk", False), ("premium", True)}
if (purchase_type, is_trial) in DISCOUNT_BYPASS_CASES:
    bypass_discount_check()
```

Benefits: easier extension, better readability, lower branching complexity, simpler testing.
Especially powerful for: permissions, feature flags, state transitions, policy engines.

---

### Golden Master Testing Before Refactoring

For legacy systems with undocumented behavior:
1. Capture existing output for a representative input set before touching code
2. Refactor the internals
3. Compare outputs — any difference is a behavioral change (deliberate or accidental)

This preserves undocumented semantics that tests don't currently cover.

---

### Edge Case and Interaction Testing

The most valuable tests target **conflicting conditions and cross-rule interactions**:

```python
# Weak — tests one condition in isolation
assert approve(premium_user)

# Strong — tests interaction between conditions
assert not approve(premium_admin_eu_with_discount)
assert approve(bulk_non_trial_user_with_discount)
```

Complex interaction cases expose hidden logic coupling that unit tests miss.

---

### Explicit Types Over Magic Strings

```python
# Fragile
return "approved"

# Better
class Decision(Enum):
    APPROVED = auto()
    REJECTED = auto()
    PENDING = auto()
```

Enums prevent silent string mismatches, improve autocomplete, and make refactoring safer.

---

## Refactoring Safety Principles

1. **Characterize before you change** — document or test current behavior first
2. **Preserve conditional hierarchy** — nesting and ordering encode meaning; flattening silently breaks it
3. **Scope-check extracted validators** — when extracting `validate_x()`, verify it was not context-gated before
4. **Test interactions, not just individual rules** — coverage of branches ≠ coverage of rule combinations
5. **Incremental over large rewrites** — small steps surface hidden assumptions; big rewrites bury them
6. **Golden master for legacy** — capture output before refactoring, compare after
7. **Review as semantic verification** — code review catches assumption mismatches that tests miss

---

## The Ground Truth Problem

There is rarely one perfect source of truth. Code, tests, requirements docs, product managers,
and production behavior often disagree. Correctness itself changes as business requirements evolve.

This means software engineering operates inside moving targets.
Engineers are fundamentally **translators** — converting ambiguous, contradictory, contextual
human rules into deterministic machine behavior. The translation is always imperfect and always provisional.

---

## When Refactoring Reveals More Than It Fixes

Bugs found during refactoring often expose:
- Hidden assumptions that were never validated
- Undocumented constraints that only the old code "knew"
- Inconsistent business rules that coexisted silently

These discoveries have value. A refactoring that finds hidden errors is doing its job —
even if the final result is "we need to ask the business team before we change this."
