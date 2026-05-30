# Agent: File Structure Reviewer

## Role

Enforce consistent project layout, naming conventions, and directory
organization across the Smart Vault monorepo (Terraform + Python Lambda).

## Trigger

Invoke when:
- A new file or directory is added
- Files are moved or renamed
- A new Lambda function is introduced
- Any `import` path changes in Python

## Project Layout Contract

```
project3-smart-vault/
├── main.tf                  # All AWS resource definitions
├── variables.tf             # Input variable declarations
├── outputs.tf               # Output value declarations
├── iam.tf                   # IAM roles and policies (isolated)
├── terraform.tfvars         # Variable values (never commit secrets)
├── .terraform.lock.hcl      # Provider lock file (commit this)
├── claude.md                # Main agent instructions
├── .agents/                 # Sub-agent specifications (this directory)
│   └── *.md
├── docs/
│   └── CHANGELOG.md         # Mandatory change log
└── lambda/
    ├── backup/
    │   └── index.py         # Entry point must be index.py
    ├── cleanup/
    │   ├── index.py         # Entry point: lambda_handler in index.py
    │   ├── runner.py        # Orchestration logic
    │   ├── policy.py        # Business rules
    │   ├── safety.py        # Decorator / guard utilities
    │   ├── explain.py       # Human-readable explanation builders
    │   └── *.py             # One concern per module
    └── restore/
        └── index.py
```

## Naming Conventions

### Python files
- `snake_case.py` — always
- Entry point: always `index.py` with `lambda_handler` as the handler function
- Module name = single responsibility (e.g., `policy.py`, `runner.py`, `safety.py`)
- No abbreviations: `config.py` not `cfg.py`

### Terraform resources
- Pattern: `<service>_<name>` (e.g., `aws_s3_bucket.archive`, `aws_lambda_function.backup`)
- Local variables: `snake_case`
- No resource names that duplicate the type: `aws_s3_bucket.bucket` is wrong

### Directories
- `kebab-case` for multi-word dirs (exception: `lambda/` sub-dirs use the function name)
- No generic names: `utils/` is acceptable only inside a Lambda package; not at repo root

## Checklist

- [ ] New Python file placed inside the correct `lambda/<function>/` package
- [ ] New Terraform resource placed in the correct `.tf` file (IAM → `iam.tf`, everything else → `main.tf`)
- [ ] No circular imports in Lambda packages
- [ ] `index.py` remains the only file that imports `boto3` clients at module level
- [ ] No test files committed to `lambda/` (tests belong in a separate `tests/` tree if added)
- [ ] `.terraform/` is in `.gitignore` and never committed
- [ ] `terraform.tfstate` is in `.gitignore` unless this is a local-only project

## Output

Report each finding as:

```
[SEVERITY] <file-or-dir>: <finding>
```

Example:
```
[BLOCK] lambda/cleanup/helpers.py: generic name — rename to describe the single concern (e.g., tag_utils.py)
[WARN]  iam.tf: new S3 policy added to main.tf — move to iam.tf
[INFO]  lambda/restore/: single-file package is acceptable at this scope
```
