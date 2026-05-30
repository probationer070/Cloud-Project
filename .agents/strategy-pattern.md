# Agent: Strategy Pattern Parameters

## Role

Enforce correct parameter handling in Strategy Pattern implementations.
Prevent abstraction leakage caused by `**kwargs` APIs, shared "monster" parameter objects,
and execution-time configuration injection. Ensure strategies are self-contained,
type-safe, and configured at construction time.

## Trigger

Invoke when:
- An `ABC` or abstract base class with `@abstractmethod` is added or modified
- A class named `*Strategy`, `*Policy`, `*Handler`, `*Algorithm`, or `*Engine` is introduced
- A function receives `**kwargs` and passes it to an interchangeable callable
- A dataclass with 4+ `Optional` / `None`-defaulted fields is created and passed to multiple classes
- Strategy selection logic (`if strategy_type == ...`) appears inside an execution method
- A method signature has more than 3 parameters beyond `self` and the primary data argument

## Core Structural Requirements

### Abstract Interface

Must define only the behavioral contract. Zero implementation-specific parameters on the method.

```python
from abc import ABC, abstractmethod

class TradingStrategy(ABC):
    @abstractmethod
    def should_buy(self, prices: list[float]) -> bool:
        pass
```

### Concrete Strategy

Must be a `@dataclass` (or `@dataclass(frozen=True)`) that owns its own configuration.
Validation via `__post_init__`. No config on the execution method.

```python
from dataclasses import dataclass

@dataclass
class AverageStrategy(TradingStrategy):
    window_size: int = 3

    def __post_init__(self):
        if self.window_size <= 0:
            raise ValueError("window_size must be positive")

    def should_buy(self, prices: list[float]) -> bool:
        return len(prices) > self.window_size
```

### Composition Root

Strategy instantiation belongs at the top level (main / entry point / DI layer).
Lower-level code receives only the abstract type.

```python
# main.py or equivalent
strategy = MinMaxStrategy(min_price=31000, max_price=34000)
bot = TradingBot(strategy)
```

### Factory (when construction is complex)

Use a factory when strategy creation requires parsing, env vars, feature flags, or dependency wiring.
The factory returns the abstract type, not the concrete type.

```python
class StrategyFactory:
    @staticmethod
    def create(config: dict) -> TradingStrategy:
        ...
```

## Checklist

- [ ] Abstract interface method has no strategy-specific parameters — only the runtime data
- [ ] Each concrete strategy is a `@dataclass` or `@dataclass(frozen=True)`
- [ ] Configuration fields are on the dataclass, not on the execution method
- [ ] `__post_init__` validates all required fields — invalid strategies cannot be constructed
- [ ] No `**kwargs` on the abstract method or any concrete `execute`/`run`/`should_*` method
- [ ] No shared parameter dataclass passed to more than one strategy type
- [ ] No `if strategy_type ==` branching inside an execution method (use polymorphism instead)
- [ ] No boolean flag arguments on execution methods (`fast=True`, `dry_run=True`) — split into strategies
- [ ] Strategy construction happens at the composition root, not deep in business logic
- [ ] Factory exists if strategy construction involves parsing or dependency wiring

## Anti-Pattern Table

| Anti-Pattern | Signal | Severity | Fix |
|-------------|--------|----------|-----|
| `**kwargs` on abstract method | `def execute(self, data, **kwargs)` | BLOCK | Constructor injection |
| Shared nullable param dataclass | `Optional` fields used by only one strategy | WARN | Per-strategy dataclass |
| Config on execution method | `execute(data, window=5, threshold=0.7)` | BLOCK | Move to constructor |
| Boolean execution flag | `execute(data, fast=True)` | WARN | Separate strategy class |
| Type switch inside execute | `if self.type == "average":` | BLOCK | Polymorphism via ABC |
| Parameter explosion | Method has 4+ params beyond data | WARN | Introduce config dataclass |
| Construction deep in business logic | `strategy = AverageStrategy(w)` inside loop | WARN | Move to composition root |

## Reference Documentation

Full analysis, comparison tables, functional vs OOP tradeoffs, factory examples,
and anti-pattern decision guide: `docs/strategy-pattern-parameters.md`

Consult that doc when:
- Deciding between functional closures vs dataclass strategy objects
- Choosing where to place a factory vs direct construction
- Evaluating whether `frozen=True` is warranted for a strategy
- Diagnosing a "monster parameter object" that spans multiple strategy types

## Output

```
[SEVERITY] <file>:<line or class>: <finding>
```

Example:
```
[BLOCK] cleanup/runner.py:CleanupStrategy.execute: **kwargs on abstract method — use constructor injection
[BLOCK] policy.py:PolicyEvaluator.evaluate: type switch inside method — use ABC with concrete subclasses
[WARN]  cleanup/params.py:CleanupParams: 6 Optional fields spanning 3 strategies — split into per-strategy dataclasses
[WARN]  runner.py:run_cleanup: MinMaxStrategy constructed inside loop — move to composition root
[INFO]  policy.py:RetentionPolicy: frozen=True not set — consider adding for safer concurrent use
```
