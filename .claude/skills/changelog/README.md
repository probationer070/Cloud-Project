# /changelog

**When to run:** Always last — after all other skills have been run and findings addressed.

## What it does

1. Reads `git diff HEAD` to see everything changed in this session
2. Infers the change type (or uses your argument)
3. Writes a populated `docs/changelog/YY-MM-DD [type] Subject.md`
4. Adds one index row to `docs/changelog/README.md`

## Command variants

| Command | Type used |
|---------|-----------|
| `/changelog` | Inferred from diff |
| `/changelog upgrade` | `upgrade` — new feature, improvement, or docs change |
| `/changelog bug` | `bug` — fix for incorrect behavior |
| `/changelog test` | `test` — new or updated tests only |

## Required fields (all must be filled)

| Field | What to write |
|-------|---------------|
| `Type` | `upgrade` / `bug` / `test` |
| `Files Changed` | Table: file · function · one-line description |
| `Why Changed` | The trigger — specific enough a future session needs no git blame |
| `Contents Diff` | Before/after snippet for every modified function; omit only for brand-new files or formatting-only changes |
| `Improvements` | Concrete: "reduced cold start by removing unused import" not "improved performance" |
| `Performance Impact` | Measurable delta, or `"none"` with honest justification |
| `Agents Consulted` | Skills run: `/security`, `/refactoring`, `/cicd`, `/design`, or `"none"` |
| `Findings Addressed` | Each `[BLOCK]`/`[WARN]` fixed with `file:line` |
| `Findings Deferred` | Any unfixed `[WARN]`/`[INFO]` with justification |

## Example

```
/changelog upgrade
```

Produces: `docs/changelog/26-06-08 [upgrade] Add Custom Quality Gate Skills.md`
Adds row to: `docs/changelog/README.md`

## Validation gates

The skill will **stop and ask** before writing if:
- `Why Changed` is empty
- `Performance Impact` is empty (not `"none"` — literally blank)
- `Contents Diff` is missing for a file with modified logic

## Tips

- Run `/changelog` even for documentation-only changes — `Performance Impact: none` is a valid and honest answer.
- The `Agents Consulted` field is the audit trail proving quality gates were run. Don't write `"none"` unless you genuinely skipped all skills.
- If a `[BLOCK]` finding was fixed, put it in `Findings Addressed` with the specific line — future sessions use this to understand why the code looks the way it does.
- Prefer `/changelog upgrade` over inferring when the diff mixes multiple small changes.
