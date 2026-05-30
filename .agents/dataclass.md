# Agent: Data Model Patterns (Python)

## Role

Enforce consistent use of Python dataclasses, TypedDicts, and type annotations
for all data structures in the Smart Vault Lambda codebase. Prevent the anti-pattern
of passing bare `dict` objects across function boundaries.

## Trigger

Invoke when:
- A new data structure is introduced (record, result, config, event)
- A function returns a `dict` that is consumed by another function
- `TypedDict` or `@dataclass` is being added or modified
- A function signature uses `dict` as a parameter type

## Type Hierarchy for This Project

Choose the right type for the job:

| Pattern | Use When | Example in This Project |
|---------|----------|------------------------|
| `@dataclass` | Mutable structured data with behavior | `PolicyResult`, `CleanupRecord` |
| `@dataclass(frozen=True)` | Immutable value objects | `SnapshotRef`, `RetentionPolicy` |
| `TypedDict` | Shape of `dict` returned by AWS SDK | `SnapshotDict`, `TagDict` |
| `NamedTuple` | Lightweight immutable records, no methods | Simple key/value pairs |
| Plain `dict` | **Never** across function boundaries — only inside a single function scope |

## Approved Dataclass Patterns

### Policy Evaluation Result

```python
from dataclasses import dataclass, field
from datetime import datetime

@dataclass
class PolicyResult:
    should_delete: bool
    reason: str
    expire_date: datetime | None
    trace: list[str] = field(default_factory=list)
```

### Snapshot Record (returned by run_cleanup)

```python
from dataclasses import dataclass

@dataclass
class SnapshotRecord:
    id: str
    name: str
    instance: str
    retain_until: str | None
    reason: str
    expire_date: datetime | None
    dry_run: bool
    trace: dict
    shadow_diff: list | None
    explanation: str | None
```

### TypedDict for AWS SDK Responses

```python
from typing import TypedDict

class SnapshotTag(TypedDict):
    Key: str
    Value: str

class SnapshotDict(TypedDict):
    SnapshotId: str
    StartTime: datetime
    Tags: list[SnapshotTag]
```

## Current Anti-Patterns in Codebase

These should be migrated when the relevant module is next touched:

| Location | Anti-Pattern | Target Pattern |
|----------|-------------|----------------|
| `runner.py:65` | `results = {"deleted": [], "kept": [], "errors": []}` bare dict | `@dataclass CleanupResults` |
| `runner.py:124` | `record = build_record(...) \| {...}` dict merge | `SnapshotRecord` dataclass |
| `cleanup/index.py:29` | `policy_metrics = {"v1": {}, "v2": {}}` | `@dataclass PolicyMetrics` |
| All Lambda handlers | `return {"statusCode": 200, "body": ...}` | `LambdaResponse` TypedDict |

## Checklist

- [ ] No function parameter typed as `dict` — use `TypedDict` or `@dataclass`
- [ ] No function return type of `dict` — define a named type
- [ ] Dataclasses used for objects that outlive a single function call
- [ ] `frozen=True` on dataclasses that represent immutable decisions (e.g., `PolicyResult`)
- [ ] `field(default_factory=list)` for mutable default fields — never `field(default=[])`
- [ ] TypedDicts for AWS SDK response shapes (one TypedDict per response type)
- [ ] `from __future__ import annotations` at top of file if using forward references
- [ ] All TypedDicts and dataclasses in a `types.py` or `models.py` module (not scattered inline)

## Migration Strategy

When converting an existing `dict` to a dataclass:
1. Define the dataclass in `<package>/models.py`
2. Update the producing function to return the dataclass
3. Update all consuming functions to use attribute access (`.id`) not key access (`["id"]`)
4. JSON serialization: add `dataclasses.asdict(record)` at the serialization boundary only

## Reference Documentation

For advanced dataclass patterns (singleton factory, auto-registration, SQL generation,
cached properties, InitVar, context managers, CLI builders, and flag reference table),
see: `docs/python-dataclass-advanced.md`

Consult that doc when:
- A new pattern feels complex enough to warrant a well-known approach
- Deciding between `frozen`, `slots`, `InitVar`, or `cached_property`
- Evaluating whether dataclasses are sufficient or a framework (Pydantic, attrs) is needed

## Output

```
[SEVERITY] <file>:<line>: <finding>
```

Example:
```
[BLOCK] runner.py:65: results dict passed across 4 function boundaries — define CleanupResults dataclass
[WARN]  runner.py:124: dict merge with | operator loses type safety — use SnapshotRecord dataclass
[INFO]  policy.py:PolicyResult: correct pattern — frozen dataclass with trace field
```
