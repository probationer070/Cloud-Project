# 26-06-06 [bug] P4 Full Teardown And Empty State Noop

**Type:** bug
**Branch / Commit:** Testo / (uncommitted infra teardown)

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| _(none — source)_ | — | No `.tf` or code files were edited. This entry records an **infrastructure teardown** plus the silent-failure that motivated it (see ERR-002). |
| AWS account `322551983602` (`ap-northeast-2`) | P4 deployed stack | 11 resource groups deleted directly via AWS CLI |

## Why Changed

`terraform destroy` on `project4-ai-chatbot` reported `Resources: 0 destroyed`
while the full P4 stack was still live and billing. Root cause: the remote state
was empty after the local→S3 backend migration never carried existing state over
(`terraform state list` returned nothing). `destroy` acts on state, not live AWS,
so it was a silent no-op and the stack was orphaned. Full diagnosis in
**ERR-002**.

The teardown was performed directly against AWS (the only reliable path given the
empty state): every P4 resource was enumerated by name/tag and deleted.

## Contents Diff

N/A — no source logic changed. Resources removed (live → absent):

```
S3        p4-chatbot-ui-jaehwan-20260606        -> removed (emptied + deleted)
APIGW v2  p4-chatbot-api (zwjpokvf9f)           -> deleted (stage/route/integration cascade)
Lambda    p4-chatbot-chatbot                    -> deleted
DynamoDB  p4-chatbot-sessions                   -> deleted
SNS       p4-chatbot-alerts (+ email sub)       -> deleted
IAM       p4-chatbot-chatbot-role (+ inline)    -> deleted
CW alarms p4-chatbot-errors, -slow-response     -> deleted
CW dash   p4-chatbot-dashboard                  -> deleted
Logs      /aws/lambda/p4-chatbot-chatbot,
          /aws/apigateway/p4-chatbot            -> deleted
CloudFront ESZEJ9Q0EI1SE (+ OAC p4-chatbot-oac) -> disabled, propagated, deleted
```

Preserved on purpose: SSM `/cloud-portfolio/gemini-api-key` (shared, P4 only
references it) and state bucket `cloud-portfolio-tfstate-jaehwan-20260606`
(the backend itself, from `bootstrap/`).

## Improvements

- Stopped a silently-orphaned P4 stack that Terraform could no longer manage.
- Confirmed teardown with a verification sweep (all resources `GONE` / `None`).
- Surfaced and documented the empty-state failure mode (ERR-002) so a future
  backend change won't repeat the silent destroy no-op.

## Performance Impact

Halted ongoing AWS charges for an orphaned stack (DynamoDB, Lambda, API Gateway,
CloudFront, S3, CloudWatch, SNS). Cost impact is the measurable change here — not
"none". No latency/runtime metric applies.

## Agents Consulted

security — teardown reviewed against the decision matrix (Terraform infra change).
Verified deletion only (no new resources, roles, or policies created), shared
resources preserved, and no orphans left after the sweep. Not a formal separate
agent run; security reasoning applied inline.

## Findings Addressed

ERR-002 (silent destroy no-op on empty remote state) — diagnosed, stack torn down,
prevention checklist recorded.

## Findings Deferred

The P4 `.tf` files still describe the now-destroyed stack, and a stale
`terraform.tfstate.backup` remains in `project4-ai-chatbot/`. A future `apply`
would recreate the whole stack. Left as-is this session (teardown only); cleanup
or re-deploy is a separate decision.
