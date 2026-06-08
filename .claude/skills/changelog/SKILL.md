# Changelog Writer

Reads the current session's work and writes a populated changelog entry following the
project's required format. Always run this last, after all other skills.

## How to use

```
/changelog              — infers type from diff (upgrade / bug / test)
/changelog upgrade      — forces [upgrade] type
/changelog bug          — forces [bug] type
/changelog test         — forces [test] type
```

## Steps

1. Run `git diff HEAD` to see all changes in this session.
2. Determine the change type:
   - `upgrade` — new feature, improvement, or documentation change
   - `bug` — fix for incorrect behavior in any environment
   - `test` — new or updated tests only
   - If a type argument was passed, use that instead of inferring.
3. Draft a subject: title case, no special characters, ≤ 60 chars.
4. Fill every required field in the template — no field may be blank or written as "TBD".
5. Write the file to `docs/changelog/YY-MM-DD [type] Subject.md`.
6. Add one index row to `docs/changelog/README.md`.

## Required fields

| Field | Rule |
|-------|------|
| `Type` | Exactly one of: `test`, `upgrade`, `bug` |
| `Files Changed` | Table: file path · function/class name · one-line description of what changed |
| `Why Changed` | The trigger or problem — specific enough a future session needs no git blame. Must not be empty. |
| `Contents Diff` | Before/after code snippet for every function whose logic was modified. Omit only if: (a) file is brand-new, OR (b) change is formatting/comment-only with no logic change. |
| `Improvements` | Concrete — "reduced Lambda cold start by removing unused import" not "improved performance" |
| `Performance Impact` | Measurable change (latency ms, memory MB, line count delta). Write "none" only if genuinely not applicable — never as a shortcut. |
| `Agents Consulted` | Comma-separated list of skills run: `/security`, `/refactoring`, `/cicd`, `/design`, or "none" |
| `Findings Addressed` | Each BLOCK/WARN finding fixed, with file:line reference |
| `Findings Deferred` | Any WARN/INFO not fixed, with justification. Write "none" if all were addressed. |

## Validation before writing

Stop and ask the user if any of these are missing:
- `Why Changed` is empty
- `Performance Impact` is empty (not "none" — literally empty)
- `Contents Diff` is omitted for a file that had prior logic

## Index row to add in `docs/changelog/README.md`

```
| YY-MM-DD | type | [Subject](YY-MM-DD%20[type]%20Subject.md) | file1.tf, file2.py |
```

## After writing

Confirm to the user:
- The changelog file path that was written
- The index row that was added to README.md
- Any field where an assumption was made (state what was assumed)
