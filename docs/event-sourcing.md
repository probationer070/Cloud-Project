# Event Sourcing — Core Concepts and Advanced Architecture

Event Sourcing stores every state-changing event instead of the latest state only.
Current state is a derived projection of replaying events in chronological order.

```
Traditional CRUD:  balance = 500 → balance = 300  (previous value lost)
Event Sourcing:    MoneyDeposited(500) → MoneyWithdrawn(200)  (full history kept)
```

---

## 1. Event Immutability

Events represent facts that already occurred. Facts must never be mutated.
Use `frozen=True` so replay is deterministic and history is protected.

```python
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum, auto

class EventType(Enum):
    ITEM_ADDED = auto()
    ITEM_REMOVED = auto()

@dataclass(frozen=True)
class Event:
    type: EventType
    data: str
    timestamp: datetime = field(default_factory=datetime.utcnow)
```

**Why `frozen=True`:** mutable events break replay consistency and create debugging nightmares.

---

## 2. Event Store

Append-only container. Unlike CRUD: no updates, no deletes, only appends.

```python
class EventStore:
    def __init__(self):
        self._events: list[Event] = []

    def append(self, event: Event):
        self._events.append(event)

    def get_all(self) -> list[Event]:
        return list(self._events)
```

Conceptually similar to: Kafka logs, Git commit history, database WAL, blockchain ledgers.

---

## 3. Replay — Rebuilding State

Current state does not exist directly. It is reconstructed by iterating events.

```python
from collections import Counter

class Inventory:
    def __init__(self, store: EventStore):
        self.store = store

    def get_items(self) -> dict[str, int]:
        counts: Counter = Counter()
        for event in self.store.get_all():
            if event.type == EventType.ITEM_ADDED:
                counts[event.data] += 1
            elif event.type == EventType.ITEM_REMOVED:
                counts[event.data] -= 1
        return {item: count for item, count in counts.items() if count > 0}
```

**Time travel:** `events[:100]` reconstructs state after the first 100 events exactly.

---

## 4. Projections

A projection transforms an event stream into a queryable read model.
The same events can produce many different views without modifying history.

```python
from collections import Counter

def top_items(events: list[Event], n: int = 5) -> list[tuple[str, int]]:
    counts: Counter = Counter()
    for event in events:
        if event.type == EventType.ITEM_ADDED:
            counts[event.data] += 1
    return counts.most_common(n)
```

Examples from identical events: current inventory, most purchased items,
user activity timelines, revenue analytics, fraud patterns, recommendation models.

**Events = write model. Projections = read model.** This separation is the foundation of CQRS.

---

## 5. Caching and Snapshotting

Replaying millions of events repeatedly is impractical.

**Cache pattern:**

```python
from functools import cache

class Inventory:
    @cache
    def get_items(self):
        ...

    def append_event(self, event: Event):
        self.store.append(event)
        self.get_items.cache_clear()  # invalidate on every new event
```

**Snapshotting:** periodically persist precomputed state so replay starts from the snapshot.

```
Without snapshot:  event 1 → 2 → 3 → ... → 1,000,000
With snapshot:     snapshot(900,000) → replay last 100,000 events
```

Store snapshots with the event sequence number they represent so replay can resume correctly.

---

## 6. Event Versioning

Schema evolution is the hardest challenge. Historical events cannot be rewritten.

**Strategy — Upcasting:** convert old event shapes to new during replay.

```python
@dataclass(frozen=True)
class Event:
    version: int
    type: EventType
    data: str
    timestamp: datetime = field(default_factory=datetime.utcnow)

def upcast(event: Event) -> Event:
    if event.version == 1:
        # v1 had flat `name`, v2 splits into first_name/last_name
        return Event(version=2, type=event.type, data=event.data, timestamp=event.timestamp)
    return event
```

Always include a `version` field on event dataclasses from day one.

---

## 7. Event Ordering and Consistency

Order matters — `Withdraw → Deposit` ≠ `Deposit → Withdraw`.

In distributed systems (clock drift, late messages, network partitions):
use sequence numbers, stream IDs, or logical clocks — never wall-clock time alone.

---

## 8. CQRS Relationship

| Side | Handles |
|------|---------|
| Command | validation, business rules, event generation |
| Query | projections, search, analytics, dashboards |

CRUD mixes writes, reads, and business logic in one model.
Event Sourcing separates them cleanly, enabling independent scaling of each.

---

## 9. Eventual Consistency

Read models may lag behind the write model by milliseconds or seconds.

```
Command → Event Store → Projection Update → Query Model
```

Design for users briefly observing stale data. This is a fundamental architectural tradeoff,
not a bug to fix.

---

## 10. Event-Driven Integration

Events naturally decouple services. One `OrderPlaced(...)` can independently trigger:
payment processing, shipping, analytics, fraud detection, and user notifications —
without tight coupling between any of them.

---

## 11. Testing Pattern

Event streams simplify domain testing — no large database mocks needed.

```python
# given → when → then
given(events=[ItemAdded("apple"), ItemAdded("banana")])
when(command=RemoveItem("apple"))
then(expected_events=[ItemRemoved("apple")])
```

---

## 12. Key Flag Reference for Event Dataclasses

| Flag / Feature | Why It Matters for Events |
|----------------|---------------------------|
| `frozen=True` | Prevents accidental mutation; makes events hashable for sets/dicts |
| `slots=True` | Reduces memory for high-volume event objects |
| `version: int` | Required for upcasting during schema evolution |
| `timestamp` with `default_factory` | Captures creation time without mutable default |
| `InitVar` | Useful for accepting raw payload that is transformed on construction |
| `field(metadata=...)` | Attach schema migration hints or event bus routing metadata |

---

## Trade-Off Summary

| Pros | Cons |
|------|------|
| Complete audit history | Higher architectural complexity |
| Deterministic replay | Harder schema evolution |
| Time-travel debugging | Event ordering challenges in distributed systems |
| Flexible projections from one stream | Increased storage usage |
| Historical analytics forever | Snapshot management overhead |
| Strong domain modeling | Eventual consistency complexity |

---

## When to Use

**Strong fit:** financial systems, version control (Git is event sourced), multiplayer games,
AI workflow pipelines, analytics platforms where historical behavior must be queryable forever.

**Weak fit:** simple CRUD dashboards, admin panels, low-value temporary data, small internal tools.
The complexity cost often outweighs the benefits for these cases.
