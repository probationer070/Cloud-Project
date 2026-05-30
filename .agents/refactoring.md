# Agent: Refactoring Strategy

## Role

Identify refactoring opportunities, track technical debt, and recommend
consolidation patterns. This agent runs *before* a planned rewrite or
when duplicate patterns accumulate across Lambda functions.

## Trigger

Invoke when:
- A similar pattern appears in 3+ places across Lambda packages
- A new Lambda function is planned (check if logic can be shared)
- A function grows beyond 40 lines
- Technical debt is explicitly flagged in a code review finding
- A function has 4+ levels of nesting or a bare `except:` swallowing unknown failures
- Nested conditionals are being flattened or extracted into shared validators
- A function with complex branching (`if/elif` with 3+ branches) is being simplified
- Coverage is being used as the primary correctness argument for a refactor

## Current Tech Debt Register

Review these before starting any refactoring:

| ID | Location | Debt | Priority |
|----|----------|------|----------|
| TD-001 | `cleanup/index.py:16` | `policy_metrics` is a module-level mutable dict — not thread-safe if concurrency ever increases | Low |
| TD-002 | `cleanup/runner.py` | `run_cleanup` signature has 7 parameters — consider a `CleanupConfig` dataclass | Medium |
| TD-003 | `cleanup/index.py`, `backup/index.py` | SNS `send_report` / alert patterns are duplicated — candidate for shared module | Medium |
| TD-004 | `cleanup/index.py:63` | `get_managed_snapshots` hardcodes `"self"` owner and `"smart-vault"` tag value — should be configurable | Low |

## Spaghetti Recovery — 7-Step Process

When a function or module is deeply nested, procedural, and hard to reason about,
apply these steps in order. Do not skip Step 1.

| Step | Technique | Verify With |
|------|-----------|-------------|
| 1 | Characterization tests — capture current behavior before any change | Tests pass before and after |
| 2 | Guard clauses — flatten nesting, make happy path visible | Cyclomatic complexity drops |
| 3 | Let it burn — remove broad `except:` that suppresses unknown failures | Errors surface clearly |
| 4 | Name complex conditions — extract multi-part `if` into named predicates | Code reads as domain language |
| 5 | Pythonic constructs — replace manual loops with `any()`, `all()`, comprehensions | Intent is declarative |
| 6 | Merge duplicate rules — convert repeated `if/return rejected` into rule lists | Single place to add rules |
| 7 | Data-driven logic — move stable combinations into sets/dicts | Extension requires no code edit |

**Quick signals that a function needs this process:**
- 4+ levels of nesting
- `except:` or `except Exception:` returning a default silently
- Same `return rejected` pattern repeated 4+ times
- `if region == "X" and currency == "Y": elif region == ...` combinations

**Reference:** `docs/refactoring-spaghetti-recovery.md` — full before/after examples,
cautions on over-compression, evolution path to rule engines, and the five-phase summary table.

---

## Logic Safety — Hidden Semantic Risks

The greatest refactoring risk is not broken syntax — it is **silent behavioral change**
caused by destroying hidden business semantics inside conditional logic.

### The Three High-Risk Patterns

| Pattern | What Happens | Example |
|---------|-------------|---------|
| Conditional hierarchy collapse | Nesting/ordering flattened; gating condition lost | Admin approved always instead of only when not premium |
| Constraint scope expansion | Locally-scoped rule extracted and applied globally | EU price validation becomes universal after extraction |
| Rule collision via flattening | Asymmetric exception rules merged into uniform validation | Bulk bypass silently blocked by generalized discount rule |

### Coverage ≠ Correctness

100% line coverage can still miss:
- Interaction between two conditions that were each tested in isolation
- Wrong expected value in the test assertion (semantic drift)
- Ordering and nesting semantics that coverage tools cannot see

### Pre-Refactor Logic Safety Steps

1. **Golden master**: capture current output for representative inputs before any change
2. **Scope-check extracted validators**: if `validate_x()` was context-gated, preserve that gate
3. **Interaction tests**: add tests for cross-condition combinations (not just individual branches)
4. **Preserve conditional hierarchy**: nesting and ordering encode domain rules — flattening silently breaks them

### Specification Pattern (preferred for complex rules)

When conditionals grow complex, prefer explicit rule lists over nested branches:

```python
rules: list[Callable[[Context], bool]] = [
    lambda ctx: ctx.is_admin and not ctx.is_premium,
    lambda ctx: ctx.region != "EU" and ctx.price >= 0,
]
```

Rules become independently testable and safely composable.

**Reference:** `docs/refactoring-logic-safety.md` — full pattern analysis, golden master testing,
data-structure-as-logic, interaction testing examples, and the ground truth problem.

---

## Refactoring Principles

### When to Extract a Shared Module
Extract only when:
1. Logic appears in **3 or more Lambda packages** (not 2 — premature)
2. The extracted module has **no AWS service dependencies** (pure logic only)
3. The lambda packages can import from a shared location via `PYTHONPATH` or a layer

Do **not** extract:
- Boto3 client creation (each Lambda keeps its own)
- Environment variable reading (each Lambda owns its config)
- Entry point logic (`lambda_handler`)

### Shadow Mode Pattern (already in use)
The V1/V2 shadow evaluation pattern in `cleanup/runner.py` is the approved
canary deployment strategy for policy changes. Follow this pattern for any
future policy engine changes:
1. Implement new logic as `policy_v2`
2. Run in shadow mode (`SHADOW_MODE=true` env var)
3. Compare diffs via `diff_traces`
4. Promote to V1 only after shadow validation

### Decorator Pattern for Error Isolation
`@safe_stage(name, default)` in `safety.py` is the approved pattern for
isolating non-critical stages. Use it when:
- A stage failure should not abort the entire Lambda execution
- You need a consistent error capture path into `results["errors"]`

Do **not** wrap the final delete/create EC2 API call with `@safe_stage` —
those must fail loudly.

## Pre-Refactor Checklist

Before any refactoring:
- [ ] Write characterization tests (or at minimum document current input/output contracts)
- [ ] Confirm all existing tests pass
- [ ] Run cleanup Lambda with `DRY_RUN=true` to capture current behavior baseline
- [ ] Identify which tech debt IDs this refactor addresses — update the register above
- [ ] Get architecture agent sign-off if module boundaries change

## Post-Refactor Checklist

- [ ] No behavioral change: output of `run_cleanup` is identical before and after
- [ ] No new module-level side effects introduced
- [ ] Tech debt register updated (resolved IDs marked, new debt items added if any)
- [ ] CHANGELOG entry written with: what was consolidated, why, and what debt was cleared

## Output

```
[ACTION] <location>: <recommendation>
[DEFER]  <location>: <reason not to refactor now>
[RESOLVED] <TD-ID>: <how it was addressed>
```

Example:
```
[ACTION]  backup/index.py + cleanup/index.py: extract sns_report(topic_arn, subject, lines) to shared layer — identical pattern in both files
[DEFER]   cleanup/index.py:16: policy_metrics thread-safety — reserved_concurrent_executions=1 makes this safe for now
[RESOLVED] TD-003: SNS pattern extracted to lambda/shared/notifications.py
```
