# 26-05-30 [bug] EC2 Free Tier Instance Type Seoul Region

**Type:** bug
**Branch / Commit:** dev / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `main.tf` | `aws_instance.backup_target` | `instance_type = "t2.micro"` → `"t3.micro"` |
| `lambda/cleanup/index.py` | module-level imports | `from cleanup.runner` → `from runner`; `from cleanup.policy` → `from policy` |
| `lambda/cleanup/runner.py` | module-level imports | All `.xxx` relative imports → plain `xxx` |
| `lambda/cleanup/policy.py` | module-level imports | `from .rule` → `from rule` |

## Why Changed

**Bug 1 — EC2 instance type:**
`terraform apply` failed with:
```
InvalidParameterCombination: The specified instance type is not eligible for Free Tier.
```
`t2.micro` is Free Tier eligible in `us-east-1` and some other regions, but **not** in `ap-northeast-2` (Seoul). The Free Tier instance type for Seoul is `t3.micro`.

**Bug 2 — Lambda import error:**
Cleanup Lambda failed at runtime with:
```
Runtime.ImportModuleError: Unable to import module 'index': No module named 'cleanup'
```
The Terraform `archive_file` data source zips the **contents** of `lambda/cleanup/` directly to the root of the zip — there is no `cleanup/` subdirectory inside the zip. The imports in `index.py` (`from cleanup.runner import ...`) assumed `cleanup` was a package on the Python path, which it is not at Lambda runtime. Same problem applied to relative imports (`.policy`, `.rule`, etc.) in `runner.py` and `policy.py` — relative imports require the module to be loaded as part of a package, but Lambda executes `index.py` as a top-level entry point, not as `cleanup.index`. Fix: all intra-package imports changed to plain module-name imports (`from runner import ...`, `from policy import ...`, etc.) which resolve correctly from the flat zip root.

## Contents Diff

**`main.tf` — `aws_instance.backup_target`**
```hcl
# Before
instance_type = "t2.micro"

# After
instance_type = "t3.micro"
```

**`lambda/cleanup/index.py`**
```python
# Before
from cleanup.runner import run_cleanup
from cleanup.policy import SnapshotPolicy

# After
from runner import run_cleanup
from policy import SnapshotPolicy
```

**`lambda/cleanup/runner.py`**
```python
# Before
from .policy import SnapshotPolicy
from .explain import diff_traces, build_explanation, aggregate_shadow_diffs
from .utils import get_tag, build_record
from .safety import safe_stage

# After
from policy import SnapshotPolicy
from explain import diff_traces, build_explanation, aggregate_shadow_diffs
from utils import get_tag, build_record
from safety import safe_stage
```

**`lambda/cleanup/policy.py`**
```python
# Before
from .rule import Rule, RuleTrace, ReplayInput, PolicyResult

# After
from rule import Rule, RuleTrace, ReplayInput, PolicyResult
```

## Improvements

- EC2 instance launches successfully in ap-northeast-2 within Free Tier limits.
- Cleanup Lambda initialises without `ImportModuleError`; all intra-module imports resolve correctly from the flat Lambda zip root.

## Performance Impact

- `t3.micro` (2 vCPU burst, 1 GB RAM) is slightly newer than `t2.micro`. No functional difference for a backup test target.
- Import fix: no performance change; cold-start time unchanged.

## Agents Consulted

architecture

## Findings Addressed

- [BLOCK] `t2.micro` not Free Tier eligible in ap-northeast-2; replaced with `t3.micro`
- [BLOCK] Cleanup Lambda `ImportModuleError`: package-qualified and relative imports fail in flat Lambda zip; replaced with plain module-name imports

## Findings Deferred

none
