# Python Data Classes — Advanced Methods Reference

Python `dataclasses` are often introduced as a lightweight replacement for boilerplate-heavy classes,
but their real power appears when they are treated as fully capable runtime objects rather than
passive data containers.

A dataclass is still a normal Python class. It supports inheritance, descriptors, decorators,
metaprogramming, context management, validation, caching, runtime introspection, and integration
with other systems such as SQL generators or CLI frameworks.

---

## 1. Singleton-like Factory

Use `ClassVar` + `@classmethod` to cache instances per environment (dev/staging/prod).
Lightweight alternative to DI frameworks.

```python
from dataclasses import dataclass
from typing import ClassVar

@dataclass
class Config:
    env: str
    db_url: str

    _instances: ClassVar[dict[str, "Config"]] = {}

    @classmethod
    def load(cls, env: str):
        if env not in cls._instances:
            cls._instances[env] = cls(env=env, db_url=f"https://{env}.db.local")
        return cls._instances[env]

dev1 = Config.load("dev")
dev2 = Config.load("dev")
print(dev1 is dev2)  # True
```

**Use for:** shared immutable config, global state without module-level variables.

---

## 2. Automatic Registration System

A decorator captures the class at import time and stores it in a global registry.

```python
from dataclasses import dataclass
from typing import dataclass_transform

REGISTRY = {}

@dataclass_transform()
def auto_register(cls):
    cls = dataclass(cls)
    REGISTRY[cls.__name__] = cls
    return cls

@auto_register
class LoginEvent:
    user_id: int
```

`dataclass_transform` signals IDEs/type checkers that the decorator produces dataclass behavior.

**Use for:** plugin systems, event buses, command handlers, AI tool registries.

---

## 3. Self-Validation with `__post_init__`

Validation logic runs immediately after field assignment. No external frameworks needed.

```python
from dataclasses import dataclass, field

@dataclass
class User:
    name: str
    age: int

    def __post_init__(self):
        if self.age < 0:
            raise ValueError("age cannot be negative")
```

**With field metadata validators:**

```python
from dataclasses import dataclass, field

def positive(value):
    if value <= 0:
        raise ValueError("must be positive")

@dataclass
class Product:
    price: int = field(metadata={"validator": positive})

    def __post_init__(self):
        validator = self.__dataclass_fields__["price"].metadata["validator"]
        validator(self.price)
```

**Dataclass validation vs Pydantic:**

| Concern | Dataclass | Pydantic |
|---------|-----------|----------|
| Internal domain models | Strong | Overkill |
| JSON/API boundary parsing | Weak | Strong |
| Nested schema coercion | Weak | Strong |
| Runtime overhead | Low | Higher |

---

## 4. SQL Schema Generator

`field(metadata=...)` + `fields()` introspection generates SQL from type definitions.

```python
from dataclasses import dataclass, field, fields

@dataclass
class User:
    id: int = field(metadata={"pk": True})
    name: str = field(metadata={"index": True})

def generate_schema(cls):
    sql = []
    for f in fields(cls):
        column = f"{f.name} TEXT"
        if f.metadata.get("pk"):
            column += " PRIMARY KEY"
        sql.append(column)
    return f"CREATE TABLE {cls.__name__.lower()} ({', '.join(sql)});"
```

**Use for:** ORM-lite systems, migration generation, code-first database design.

---

## 5. Cached Properties

Use `functools.cached_property` for expensive deterministic computations.
Works even with `frozen=True` (bypasses immutability via descriptor internals).

```python
from dataclasses import dataclass
from functools import cached_property
from urllib.parse import urlparse

@dataclass(frozen=True)
class URLObject:
    url: str

    @cached_property
    def parsed(self):
        return urlparse(self.url)
```

**Use for:** URL parsing, regex compilation, tokenization, embedding generation.

---

## 6. Self-Building CLI Parser

Dataclass field names, types, and defaults map directly to `argparse` arguments.

```python
from dataclasses import dataclass, fields
import argparse

@dataclass
class Config:
    host: str
    port: int = 8080

def build_parser(cls):
    parser = argparse.ArgumentParser()
    for f in fields(cls):
        parser.add_argument(f"--{f.name}", type=f.type, default=f.default)
    return parser
```

**Eliminates:** duplicate CLI definitions, sync issues between config and argument parser.

---

## 7. Context Manager Dataclasses

Implement `__enter__` / `__exit__` inside a dataclass to combine resource metadata with lifecycle.

```python
from dataclasses import dataclass

@dataclass
class FileManager:
    path: str
    mode: str

    def __enter__(self):
        self.file = open(self.path, self.mode)
        return self.file

    def __exit__(self, exc_type, exc, tb):
        self.file.close()
```

---

## 8. `InitVar` — Temporary Initialization Data

`InitVar` fields appear in `__init__` and `__post_init__` but are NOT stored as instance attributes.
Ideal for secrets and one-time initialization inputs.

```python
from dataclasses import dataclass, field, InitVar

@dataclass
class User:
    email: str
    password_hash: str = field(init=False)
    raw_password: InitVar[str]

    def __post_init__(self, raw_password):
        self.password_hash = hash(raw_password)
```

**Security advantage:** sensitive values are processed without persisting in object state,
reducing accidental exposure through serialization, logging, or memory inspection.

---

## Key Flags Reference

| Flag / Feature | Effect | Best For |
|----------------|--------|----------|
| `frozen=True` | Immutable object; hashable | Value objects, cache keys, concurrency |
| `slots=True` | Lower memory, faster access, no `__dict__` | High-volume objects, real-time systems |
| `eq=True` (default) | Auto `__eq__` from fields | Value comparison |
| `order=True` | Auto `__lt__`, `__gt__`, etc. | Sorting, priority queues |
| `ClassVar` | Not a dataclass field; shared across instances | Registries, caches |
| `InitVar` | Init-only parameter, not stored | Secrets, transient inputs |
| `field(default_factory=...)` | Safe mutable defaults | Lists, dicts as field defaults |
| `field(metadata=...)` | Arbitrary metadata attached to field | Validators, schema generators |
| `cached_property` | Compute-once, cache on instance | Expensive derived values |

---

## Pattern Matching Integration

Modern Python dataclasses integrate with structural pattern matching.

```python
@dataclass
class Event:
    type: str
    payload: dict

match event:
    case Event(type="login", payload=data):
        print(data)
```

---

## When Dataclasses Are Sufficient

- Internal domain models
- Configuration objects
- Lightweight validation
- Reflection / introspection
- Structured runtime metadata
- Medium-complexity architectures

## When to Reach for a Framework

| Need | Tool |
|------|------|
| Deep nested validation + JSON coercion | Pydantic |
| Full ORM + migrations | SQLAlchemy |
| Rich validation with converters | attrs |
| API request/response contracts | Pydantic or Marshmallow |
