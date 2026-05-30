# SOLID Principles — Python Reference

SOLID is about managing change without causing cascading complexity — not about maximizing abstraction or writing more classes.

| Principle | One-line meaning | Pythonic lever |
|-----------|-----------------|----------------|
| SRP | One reason to change | Small functions, focused modules |
| OCP | Extend without modifying stable code | Protocols, callables, registries |
| LSP | Subtypes preserve expected behavior | Behavior-focused interfaces |
| ISP | Prefer small focused contracts | Structural typing, small Protocols |
| DIP | Depend on abstractions, not implementations | Constructor injection, composition root |

---

## 1. SRP — Single Responsibility Principle

One class/module/function = one cohesive responsibility.
SRP does **not** mean one method per class — it means one reason to change.

**Anti-pattern:** class that reads, calculates, formats, and emails all at once.

```python
# Bad — multiple unrelated reasons to change
class ReportManager:
    def generate(self):
        self.read_csv()
        self.calculate_metrics()
        self.save_pdf()
        self.send_email()
```

**Fix:** separate by responsibility.

```python
class Reader:      ...   # changes when data source changes
class Calculator:  ...   # changes when business rules change
class Writer:      ...   # changes when output format changes
```

**Signal to split:** changing PDF formatting risks breaking CSV parsing, or database updates affect analytics logic.

---

## 2. OCP — Open/Closed Principle

Open for extension, closed for modification. New behavior → new code, not edits to stable code.

**Anti-pattern:** branching on type inside orchestration logic.

```python
# Bad — adding a new metric requires editing this function
if metric_type == "revenue":   ...
elif metric_type == "customers": ...
elif metric_type == "growth":   ...
```

**Fix:** polymorphism via Protocol.

```python
from typing import Protocol
import pandas as pd

class Metric(Protocol):
    def compute(self, df: pd.DataFrame) -> dict: ...

class RevenueMetric:
    def compute(self, df): return {"revenue": df["sales"].sum()}

class CustomerMetric:
    def compute(self, df): return {"customers": df["user"].nunique()}

# Orchestration never changes when new metrics are added
def run_all(metrics: list[Metric], df: pd.DataFrame) -> dict:
    return {k: v for m in metrics for k, v in m.compute(df).items()}
```

**Pythonic OCP levers:** Protocols, callables, decorator registries, higher-order functions, plugin lists.

---

## 3. LSP — Liskov Substitution Principle

A subtype must be usable anywhere its parent is expected without surprising the caller.
The issue is **behavioral compatibility**, not inheritance syntax.

**Anti-pattern:**

```python
class Bird:
    def fly(self): ...

class Penguin(Bird):
    def fly(self): raise NotImplementedError()  # violates caller expectations
```

**Fix:** model actual capabilities, not overly broad hierarchies.

```python
class Flyable(Protocol):
    def fly(self): ...

class Swimmable(Protocol):
    def swim(self): ...
```

**Common LSP violations:**
- `raise NotImplementedError()` inside supposedly supported behavior
- Child returns `generator` where parent returns `list` (different iteration semantics)
- Child has hidden side effects (mutates shared state) that parent did not

---

## 4. ISP — Interface Segregation Principle

Clients should not depend on methods they do not use. Prefer many small contracts over one large one.

**Anti-pattern:**

```python
class Worker(Protocol):
    def work(self): ...
    def eat(self): ...
    def sleep(self): ...
    def attend_meeting(self): ...
```

Most implementations only need one or two of these.

**Fix:** split by capability.

```python
class Runnable(Protocol):
    def run(self): ...

class Persistable(Protocol):
    def save(self): ...
```

**Python advantage:** structural typing makes small Protocols nearly zero-cost. A class satisfies a Protocol by having the right methods — no explicit `implements` declaration needed.

---

## 5. DIP — Dependency Inversion Principle

High-level modules should not depend on low-level implementations. Both should depend on abstractions.

**Anti-pattern:**

```python
class ReportService:
    def __init__(self):
        self.db = PostgreSQLDatabase()   # tightly coupled to concrete class
```

**Fix:** inject the abstraction.

```python
class Database(Protocol):
    def query(self, sql: str) -> list: ...

class ReportService:
    def __init__(self, db: Database):   # depends on abstraction
        self.db = db
```

**Composition root** (main / entry point) wires concrete types:

```python
db = PostgreSQLDatabase()
service = ReportService(db)
```

Core logic never touches concrete infrastructure. This enables mocking, runtime replacement, and decoupled testing.

---

## Refactoring Pattern: Messy → SOLID

**Before:**

```python
def generate_report():
    read_csv()
    calculate()
    save_json()
    upload_s3()
```

**After:** inject all dependencies, each with one responsibility.

```python
@dataclass
class SalesReportGenerator:
    reader: DataReader
    writer: DataWriter
    metrics: list[Metric]

    def generate(self, input_file: str, output_file: str) -> None:
        df = self.reader.read(input_file)
        report = {k: v for m in self.metrics for k, v in m.compute(df).items()}
        self.writer.write(output_file, report)
```

Result: each dependency is independently testable, swappable, and extensible.

---

## Protocol vs ABC

| Concern | `Protocol` | `ABC` |
|---------|-----------|-------|
| Coupling | Loose (structural) | Tight (explicit subclass) |
| Runtime enforcement | Weak | Strong (`@abstractmethod`) |
| Third-party compatibility | Yes — anything with right methods | No — must inherit |
| Pythonic trend | Modern preference | Legacy / enforcement-critical cases |

Modern Python favors `Protocol + composition` over deep inheritance hierarchies.

---

## SOLID in Functional Style

SOLID is not OOP-only. The ideas map directly to functional Python:

| Principle | Functional form |
|-----------|----------------|
| SRP | Small pure functions with one job |
| OCP | Pass new functions into pipelines: `metrics = [revenue_fn, customer_fn]` |
| LSP | Functions with same signature are interchangeable |
| ISP | Single-argument callables instead of large interfaces |
| DIP | `def generate_report(reader, writer, metrics)` — inject functions as dependencies |

---

## Anti-Pattern Table

| Anti-Pattern | Principle Violated | Signal | Fix |
|-------------|-------------------|--------|-----|
| God class (read + calculate + format + send) | SRP | Class changes for unrelated reasons | Split into focused classes/functions |
| `if type == "X": elif type == "Y":` in orchestration | OCP | Adding behavior requires editing stable code | Protocol + polymorphism |
| Subclass raises `NotImplementedError` for inherited method | LSP | Caller gets surprise exception | Redesign interface to actual capabilities |
| One giant Protocol with 10 methods | ISP | Implementors stub out most methods | Split into small focused Protocols |
| `self.db = PostgreSQLDatabase()` inside constructor | DIP | Impossible to test without real DB | Inject via constructor parameter |
| Inheritance where composition would do | LSP / ISP | Deep hierarchy for trivial variation | Composition + Protocol |

---

## When SOLID Is Worth the Complexity

**High value:** large teams, long-lived systems, code that changes frequently, anything with multiple swap-in implementations (storage, auth, metrics, AI providers).

**Lower value:** small scripts, one-off tools, prototypes, code that will never be extended.

Pragmatic Python often combines: selective abstraction + Protocols + dataclasses + functions + minimal inheritance. Not everything needs a deep object hierarchy.
