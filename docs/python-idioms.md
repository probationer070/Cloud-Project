# Pythonic Code Refactoring — Idioms and Design Philosophy

Pythonic refactoring aligns code with Python's philosophy: readability, simplicity,
explicitness, and leveraging the standard library. The goal is not shorter code —
it is lower cognitive complexity, safer resource handling, and more expressive intent.

---

## 1. Functions Over Unnecessary Classes

A class that holds no state and provides no polymorphism is just a namespace.

```python
# Non-Pythonic — class as namespace
class StringUtils:
    def clean_text(self, text):
        return text.strip().lower()

# Pythonic — plain function
def clean_text(text: str) -> str:
    return text.strip().lower()
```

**Use a class when:** managing state, enforcing invariants, modeling domain entities,
implementing lifecycle behavior, or enabling polymorphism.

**Avoid a class when:** it has no `__init__` state, all methods are independent,
and nothing would be lost by making them module-level functions.

"Java-style Python" — wrapping every function in a class — creates indirection without benefit.

---

## 2. Context Managers for Resource Safety

Manual `close()` calls are silently skipped when exceptions occur.

```python
# Risky — close() skipped on exception
f = open("data.txt")
data = f.read()
f.close()

# Safe — guaranteed cleanup
with open("data.txt") as f:
    data = f.read()
```

Context managers guarantee deterministic cleanup via `__enter__` / `__exit__` regardless of
exceptions, early returns, or unexpected branches.

**Use for:** files, database connections, thread locks, network sockets, temporary resources,
any resource with an acquire/release lifecycle.

---

## 3. Type Annotations — Self-Documenting Interfaces

Type hints are lightweight contracts between components. They do not enforce runtime validation
by default — their value is developer tooling, static analysis, and refactoring safety.

```python
from typing import Optional

def find_user(user_id: int) -> Optional[str]:
    ...
```

**Useful constructs:** `Optional`, `Union`, `Literal`, `Protocol`, `TypedDict`,
`Generic`, `Callable`, `Iterator`, `Sequence`.

**When to annotate:** all public function signatures, dataclass fields, module-level constants.
Internal one-liners or obvious local variables can omit annotations.

---

## 4. `@dataclass` for Structured Data

Loose argument lists are fragile — ordering errors are silent and hard to spot.

```python
# Fragile — argument order matters, no names visible at call site
save_entry(description, calories, date)

# Structured — explicit, self-documenting, auto-generated __init__/__repr__/__eq__
from dataclasses import dataclass, field
from datetime import date

@dataclass
class Entry:
    description: str
    calories: int
    date: str = field(default_factory=lambda: str(date.today()))
```

**Key options:**
| Flag | Effect |
|------|--------|
| `frozen=True` | Immutable; enables hashing |
| `slots=True` | Lower memory, faster access |
| `kw_only=True` | All fields keyword-only |
| `order=True` | Auto `__lt__`, `__gt__` for sorting |

**Best for:** DTOs, configuration models, event payloads, immutable value objects.

---

## 5. EAFP — Easier to Ask Forgiveness than Permission

Python favors attempting the operation and handling failure explicitly over
pre-checking every condition.

```python
# LBYL (Look Before You Leap) — redundant check + race condition risk
if os.path.exists(path):
    with open(path) as f:
        ...

# EAFP — attempt it, handle failure explicitly
try:
    with open(path) as f:
        data = f.read()
except FileNotFoundError:
    print("Missing file")
```

EAFP reduces branching, avoids TOCTOU race conditions, and aligns with Python's exception model.

**EAFP does NOT mean:** `except Exception: pass` or ignoring errors broadly.
Catch only the specific exceptions you expect. Handle failure intentionally.

---

## 6. Standard Library — Use It, Don't Reimplant It

### `pathlib` for Paths

```python
# Fragile string concatenation
path = "data/" + filename

# Safe, readable, cross-platform
from pathlib import Path
path = Path("data") / filename
```

### `logging` Instead of `print`

```python
# print — no timestamp, no severity, no centralized control
print("Application started")

# logging — structured, leveled, configurable
import logging
logging.info("Application started")
```

Log levels: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`.
Use `logging.getLogger(__name__)` per module for namespaced output.

### Generators for Large Data

```python
# Loads everything into memory
lines = open(path).readlines()

# Streams lazily — O(1) memory
def read_lines(path: str):
    with open(path) as f:
        for line in f:
            yield line
```

Generators are essential for: log streaming, CSV processing, AI dataset pipelines,
ETL workflows, any data larger than comfortable RAM.

---

## 7. `__main__` Guard for Entry Points

Scripts that execute immediately on import cause hidden side effects when imported as modules.

```python
def main() -> None:
    print("Running application")

if __name__ == "__main__":
    main()
```

This separates: execution from definition, enables testing without side effects,
supports modular reuse, and enables CLI integration via `python -m module`.

---

## Refactoring Comparison Table

| Concern | Non-Pythonic | Pythonic |
|---------|-------------|----------|
| Structure | Monolithic utility classes | Functions + focused data models |
| Resources | Manual `close()` / `release()` | Context managers |
| Data flow | Loose positional arguments | `@dataclass` with named fields |
| Paths | String concatenation | `pathlib.Path` |
| Error handling | Defensive pre-checks everywhere | EAFP with specific `except` |
| Visibility | `print()` debugging | Structured `logging` |
| Entry point | Module-level execution | `if __name__ == "__main__"` |
| Memory | Eager `list` loading | Lazy generators |
| Interfaces | Implicit assumptions | Type annotations |

---

## Common Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Stateless class wrapping functions | Unnecessary indirection | Module-level functions |
| `f.open()` without `with` | Resource leak on exception | Context manager |
| `print()` for production output | No timestamps, levels, or control | `logging` |
| `"dir/" + filename` path building | OS-dependent, error-prone | `pathlib` |
| `if os.path.exists():` before open | Race condition, redundant check | EAFP `try/except FileNotFoundError` |
| `open(path).readlines()` on large files | Memory exhaustion | Generator with `yield` |
| `if __name__` guard missing | Side effects on import | Add `main()` + guard |
| No type annotations on public API | Hidden contracts, weak tooling | Add annotations to signatures |

---

## Core Philosophy (The Zen Applied)

- **Explicit is better than implicit** — type annotations, named fields, specific `except`
- **Simple is better than complex** — functions over classes when state is absent
- **Readability counts** — code is read far more often than written
- **Practicality beats purity** — use the idiom that is clearest in context, not the cleverest
