# Strategy Pattern — Parameter Handling Reference

The Strategy Pattern separates algorithms from the code that uses them.
The hidden architectural risk appears when different strategies need different configuration:
the caller starts understanding implementation details of concrete strategies, leaking the abstraction.

---

## The Wrong Approaches

### ❌ `**kwargs` Injection

```python
strategy.run(data, **config)
```

Problems:
- Interface accepts "literally anything" — type safety collapses
- Silent contracts: strategy expects `kwargs["window_size"]` but nothing enforces it
- Renaming a key (`window_size → moving_average_window`) silently breaks callers
- IDE autocomplete, inference, and required-argument checking all degrade

`**kwargs` is acceptable in: framework internals, decorators, adapters, plugin forwarding layers.
It is poor for core domain interfaces.

---

### ❌ Shared Parameter Dataclass ("Monster Object")

```python
@dataclass
class StrategyParams:
    window_size: int | None = None
    min_price: float | None = None
    max_price: float | None = None
    compression_level: int | None = None
```

Problems:
- Each strategy receives fields it never uses (low cohesion)
- Every strategy becomes coupled to every other strategy's config
- Adding one strategy changes the shared schema for all strategies
- Validation must now answer "which fields are required for which strategy"

Signal: when you see `None`-defaulted fields that only one strategy cares about,
this object is trying to serve too many masters.

---

## The Correct Solution — Constructor Injection

> Configure the strategy when it is created. The strategy is fully configured before execution.

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass

class TradingStrategy(ABC):
    @abstractmethod
    def should_buy(self, prices: list[float]) -> bool:
        pass

@dataclass
class AverageStrategy(TradingStrategy):
    window_size: int = 3

    def should_buy(self, prices: list[float]) -> bool:
        return len(prices) > self.window_size

@dataclass
class MinMaxStrategy(TradingStrategy):
    min_price: float
    max_price: float

    def should_buy(self, prices: list[float]) -> bool:
        return prices[-1] < self.min_price
```

The caller only sees:
```python
strategy.should_buy(prices)
```
— not the internal configuration details.

---

## Composition Root

Concrete strategies are selected at the top level of the application (main/entry point).
Lower-level code depends only on the abstract interface.

```python
# Composition root (main.py or equivalent)
strategy = MinMaxStrategy(min_price=31000, max_price=34000)
bot = TradingBot(strategy)
```

`TradingBot` knows `"I have a TradingStrategy"` — not `"I use MinMaxStrategy with min_price"`.

---

## Validation at Construction Time

Invalid strategies become impossible to execute. Fail at construction, not at runtime.

```python
@dataclass
class AverageStrategy:
    window_size: int

    def __post_init__(self):
        if self.window_size <= 0:
            raise ValueError("window_size must be positive")
```

---

## Immutable Strategies

Use `frozen=True` when the strategy has no reason to change after creation.

```python
@dataclass(frozen=True)
class AverageStrategy:
    window_size: int
```

Benefits: safer concurrency, deterministic behavior, easier caching, reproducible execution.
Especially valuable in: financial systems, AI pipelines, async processing, distributed systems.

---

## Factory for Complex Construction

When strategy creation itself is complex (parsing config files, env vars, feature flags):

```python
class StrategyFactory:
    @staticmethod
    def create(config: dict) -> TradingStrategy:
        if config["type"] == "average":
            return AverageStrategy(window_size=config["window_size"])
        elif config["type"] == "minmax":
            return MinMaxStrategy(
                min_price=config["min_price"],
                max_price=config["max_price"],
            )
        raise ValueError(f"Unknown strategy type: {config['type']}")
```

Factories centralize: parsing, validation, construction, dependency wiring.

---

## Functional Alternative

Closures can implement lightweight strategies without classes:

```python
def average_strategy(window_size: int):
    def should_buy(prices: list[float]) -> bool:
        return len(prices) > window_size
    return should_buy
```

| Concern | Functional closure | Dataclass strategy |
|---------|--------------------|--------------------|
| Boilerplate | Minimal | Slightly more |
| Type hints on config | Weak | Strong |
| Runtime introspection | Hard | Easy (`fields()`) |
| Serialization | Hard | Easy (`asdict()`) |
| `__post_init__` validation | Not available | Available |
| Extensibility (subclassing) | None | Full |

Use functional style for simple, stateless, short-lived strategies.
Use dataclass strategy objects when config is non-trivial or introspection matters.

---

## Interface Size Rule

Execution method parameters should be minimal — ideally just the runtime data.

```python
# Good
strategy.execute(data)

# Bad — config leaking into execution
strategy.execute(data, window_size=5, threshold=0.7, retries=3, mode="fast")
```

---

## Anti-Pattern Table

| Anti-Pattern | Signal | Fix |
|-------------|--------|-----|
| `**kwargs` in strategy interface | Type safety collapses; hidden contracts | Constructor injection |
| Shared "monster" param dataclass | `None`-heavy fields across strategies | Per-strategy dataclass config |
| Config passed at execution time | Method has 4+ params beyond the data | Move config to constructor |
| Boolean flags on execute | `fast=True`, `dry_run=True` | Split into separate strategy classes |
| Runtime `if strategy_type ==` inside execute | Switch on type inside the method | Polymorphism via ABC |
| Parameter explosion | `execute(a, b, c, d, e, f)` | Missing abstraction — introduce a config dataclass |

---

## Real-World Examples

Constructor injection is the dominant pattern in:
ML model pipelines, retry policies, authentication providers,
payment gateways, serialization engines, compression libraries, AI agent tools.

---

## Summary Decision Guide

| Situation | Recommendation |
|-----------|----------------|
| Strategies share zero config fields | Constructor injection, each strategy owns its config |
| Construction is complex / from config file | Add a `StrategyFactory` |
| Strategy is truly stateless and trivial | Functional closure |
| Config must be introspectable at runtime | Dataclass with `fields()` |
| Strategy will be used across threads | Add `frozen=True` |
| Multiple optional fields depending on type | Per-subclass dataclass, not a shared nullable object |
