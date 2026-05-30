# Advanced Python Features — Code Quality and Architecture Reference

These features are not syntax tricks. Each one addresses a recurring architectural problem:
coupling, mutability, concurrency safety, resource management, or readability.

| Theme | Feature |
|-------|---------|
| Performance optimization | `functools.cache` |
| Architectural decoupling | `typing.Protocol` |
| Immutability & predictability | `dataclasses.replace` |
| Declarative iteration | `itertools.pairwise` |
| Expressive control flow | Walrus operator `:=` |
| Cross-platform reliability | `pathlib` |
| Explicit exception ignoring | `contextlib.suppress` |
| Async & concurrency safety | `contextvars` |
| Declarative branching | `match` with guards |
| Dynamic resource management | `contextlib.ExitStack` |

---

## 1. `functools.cache` — Memoization

Stores function results in memory; reuses them when the same arguments are passed again.

```python
from functools import cache

@cache
def fibonacci(n: int) -> int:
    if n < 2:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
```

**Use when:** pure function called repeatedly with the same args (recursion, config loading,
SQL result caching, expensive parsing).

**Constraints:** arguments must be hashable; cached values live until program exit.
Use `functools.lru_cache(maxsize=N)` when memory bound is needed.

---

## 2. `typing.Protocol` — Structural Typing

An object satisfies a Protocol if it has the required methods — no inheritance needed.

```python
from typing import Protocol

class Storage(Protocol):
    def save(self, data: str) -> None: ...

class FileStorage:
    def save(self, data: str) -> None:
        print(f"Saving {data}")

def persist(storage: Storage, data: str) -> None:
    storage.save(data)

persist(FileStorage(), "hello")   # works — no `class FileStorage(Storage)` required
```

**Use when:** dependency injection, strategy pattern, plugin systems, mock testing,
service abstraction layers where you don't control third-party classes.

**vs ABC:** Protocol = structural (loose coupling, third-party compatible).
ABC = nominal (explicit inheritance, runtime `@abstractmethod` enforcement).

---

## 3. `dataclasses.replace` — Immutable State Updates

Creates a modified copy of a frozen dataclass without mutating the original.

```python
from dataclasses import dataclass, replace

@dataclass(frozen=True)
class User:
    name: str
    score: int

user = User("Alice", 10)
updated = replace(user, score=20)   # user unchanged; updated is a new instance
```

**Use when:** event sourcing, state machines, workflow systems, financial transactions,
any pattern where explicit state transitions matter and side effects must be avoided.

**Analogy:** mirrors immutable update patterns from Redux, React state, and distributed systems.

---

## 4. `itertools.pairwise` — Adjacent Pair Iteration

Iterates over neighboring element pairs without manual index arithmetic.

```python
from itertools import pairwise

numbers = [10, 15, 21, 30]

for a, b in pairwise(numbers):
    print(b - a)   # 5, 6, 9
```

**Use when:** time-series deltas, log processing, trend detection, sequence validation,
any case where the relationship between consecutive elements matters more than individual values.

**Replaces:** error-prone `for i in range(len(seq) - 1): seq[i], seq[i+1]` patterns.

---

## 5. Walrus Operator `:=` — Assignment Expressions

Assigns a value inside an expression, eliminating redundant computation.

```python
# Stream reading
while (line := file.readline()):
    print(line.strip())

# Regex with result reuse
import re
if match := re.search(r"\d+", text):
    print(match.group())
```

**Use when:** stream processing, regex matching, file reading loops, parsing pipelines
where the computed value is needed both in the condition and the body.

**Caution:** overuse compresses code at the cost of readability. Use only when it
simplifies logic, not to show off one-liners.

---

## 6. `pathlib` — Object-Oriented File Paths

Replaces fragile OS-dependent string concatenation with path objects.

```python
from pathlib import Path

config = Path("configs/settings.json")
if config.exists():
    print(config.read_text())

# Recursive discovery
for file in Path("logs").glob("*.txt"):
    print(file.name)
```

**Use when:** any filesystem operation — reading, writing, recursive discovery, build systems,
config management. Always prefer `pathlib` over `os.path` string manipulation.

**Key methods:** `.exists()`, `.read_text()`, `.write_text()`, `.glob()`, `.rglob()`,
`.parent`, `.stem`, `.suffix`, `/` operator for joining paths.

---

## 7. `contextlib.suppress` — Explicit Exception Ignoring

Ignores specified exceptions without verbose `try-except-pass` blocks.

```python
from contextlib import suppress
from pathlib import Path

with suppress(FileNotFoundError):
    Path("temp.txt").unlink()   # silently skip if file doesn't exist
```

**Use when:** optional cleanup, temporary file removal, best-effort resource release,
graceful shutdown logic where the failure genuinely does not matter.

**Caution:** suppress only the specific exceptions you expect. Broad suppression hides bugs.
Never use `suppress(Exception)` — that is the context manager equivalent of a bare `except:`.

---

## 8. `contextvars` — Async-Safe Context Storage

Provides task-local storage that does not leak between concurrent async tasks.

```python
import contextvars

request_id = contextvars.ContextVar("request_id")

request_id.set("REQ-123")
print(request_id.get())   # "REQ-123" — isolated per task in async context
```

**Use when:** request tracing, correlation IDs, user session tracking, distributed logging
in async services where global variables would leak across concurrent requests.

**Critical insight:** solves per-request state propagation without threading globals or
passing IDs through every function call. Essential in `asyncio`-based Lambda handlers
or FastAPI services handling concurrent requests.

---

## 9. `match` with Guards — Structural Pattern Matching

Declarative branching on data structure and values simultaneously.

```python
def classify(data: dict) -> str:
    match data:
        case {"status": 200, "data": payload} if payload:
            return "success"
        case {"status": 404}:
            return "not found"
        case _:
            return "unknown"
```

**Use when:** JSON/API response parsing, command interpreters, validation systems,
event dispatching — any place where `if-elif-else` chains grow complex enough to obscure intent.

**Guards:** `case X if condition:` narrows a structural match with an additional predicate.
This replaces the common `if isinstance(x, Y) and x.field == Z:` pattern.

---

## 10. `contextlib.ExitStack` — Dynamic Context Management

Manages a variable number of context managers determined at runtime.

```python
from contextlib import ExitStack

files = ["a.txt", "b.txt", "c.txt"]

with ExitStack() as stack:
    opened = [stack.enter_context(open(f)) for f in files]
    for file in opened:
        print(file.read())
# all files closed automatically on exit, even if one raises
```

**Use when:** multi-file processing, dynamic database connection pools, transaction
orchestration, resource management where the number of resources is unknown at write time.

**Key insight:** `ExitStack` is programmable resource management — cleanup is guaranteed
regardless of how many resources were opened or which one failed.

---

## Feature Selection Guide

| Situation | Reach For |
|-----------|-----------|
| Pure function called many times with same args | `functools.cache` |
| Need to swap implementations without inheritance | `typing.Protocol` |
| State transition that must not mutate the original | `dataclasses.replace` |
| Iterating consecutive pairs in a sequence | `itertools.pairwise` |
| Value needed in both condition and body | Walrus `:=` |
| Any file/directory operation | `pathlib` |
| Optional cleanup where failure is acceptable | `contextlib.suppress` |
| Per-request state in async code | `contextvars` |
| Dispatching on data shape + conditions | `match` with guards |
| Unknown number of resources to manage | `contextlib.ExitStack` |
