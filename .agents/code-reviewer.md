# Agent: Code Reviewer

## Role

Review Python and Terraform code for correctness, style conformance,
error handling completeness, and maintainability. This agent does not
make judgment calls about architecture or security — those are separate agents.

## Trigger

Invoke on every code change before commit.

## Python Checklist

### Type Annotations
- [ ] All function signatures have parameter and return type annotations
- [ ] `boto3` responses typed with `TypedDict` or `Any` — never bare `dict`
- [ ] No implicit `Optional` — use `X | None` (Python 3.10+) or `Optional[X]`

### Error Handling
- [ ] `except Exception as e` always logs `str(e)` before swallowing
- [ ] No bare `except:` clauses
- [ ] Boto3 calls inside try/except; caught exceptions appended to `errors` list, not raised
- [ ] AWS throttling errors (`ClientError` with code `RequestLimitExceeded`) handled with backoff or at minimum logged distinctly

### Code Quality
- [ ] No function longer than 40 lines (split if exceeded)
- [ ] No nested functions deeper than 2 levels
- [ ] No mutable default arguments: `def f(x=[])` is always wrong
- [ ] `os.environ[]` for required env vars (raises `KeyError` on missing — intentional)
- [ ] `os.getenv("KEY", default)` for optional env vars with defaults
- [ ] f-strings preferred over `%` or `.format()`
- [ ] List comprehensions preferred over `map`/`filter` for simple transforms

### Boto3 Patterns
- [ ] Clients created at module level (reuse Lambda container warm starts)
- [ ] Paginator used when listing resources (never assume single-page response):
  ```python
  # WRONG
  ec2.describe_snapshots(...)["Snapshots"]
  
  # RIGHT (or document why pagination is not needed)
  paginator = ec2.get_paginator("describe_snapshots")
  for page in paginator.paginate(...):
      ...
  ```
- [ ] No hardcoded region strings — use `os.environ["AWS_REGION"]` if needed

### Logging
- [ ] Use `print(f"[{MODULE}] ...")` as the standard logging pattern (CloudWatch captures stdout)
- [ ] Log at start and end of every significant operation
- [ ] Log IDs and counts, not full object payloads (avoid logging sensitive data)

## Error Recording Protocol

When a finding reveals an **existing defect in running code** (not a hypothetical or style issue):

1. Note it as `[BLOCK]` in the output below
2. After the fix is confirmed, create `docs/error/ERR-NNN-short-description.md` from the template
3. Add an index row to `docs/error/README.md`
4. Update this agent's checklist if the pattern was not previously covered
5. Add a CHANGELOG entry referencing the ERR-NNN ID

See `CLAUDE.md §7` and `docs/error/README.md` for the full process.

## Terraform Checklist

### Resource Definitions
- [ ] Every resource has `tags = var.common_tags` (or `merge(var.common_tags, {...})`)
- [ ] `lifecycle` blocks used where destruction requires care
- [ ] `depends_on` only when implicit dependency graph is insufficient — document why
- [ ] No hardcoded account IDs or ARNs; use data sources or variables

### Variable Usage
- [ ] All variables declared in `variables.tf` with `description` and `type`
- [ ] No variable without a `description`
- [ ] Sensitive variables (API keys, passwords) marked `sensitive = true`
- [ ] `tostring()` used when passing number variables into string env vars

### Outputs
- [ ] Sensitive outputs marked `sensitive = true`
- [ ] All outputs declared in `outputs.tf`, not inline in `main.tf`

## Output

```
[SEVERITY] <file>:<line>: <finding>
```

Example:
```
[BLOCK] lambda/cleanup/runner.py:87: bare except clause swallows all errors silently
[WARN]  lambda/cleanup/index.py:62: describe_snapshots not paginated — fails silently if >1000 snapshots
[WARN]  variables.tf:14: restore_api_key missing sensitive = true
[INFO]  lambda/backup/index.py:5: boto3 client created at module level — correct pattern
```
