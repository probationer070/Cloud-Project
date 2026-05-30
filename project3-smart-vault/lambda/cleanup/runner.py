from policy import SnapshotPolicy
from explain import diff_traces, build_explanation, aggregate_shadow_diffs
from utils import get_tag, build_record
from safety import safe_stage


def inc_metric(policy_metrics, version, reason, action):
    key = f"{reason}:{action}"
    
    if version not in policy_metrics:
        policy_metrics[version] = {}
        
    policy_metrics[version][key] = (
        policy_metrics[version].get(key, 0) + 1
    )


@safe_stage("shadow_evaluation", default=None)
def run_shadow_evaluation(
    policy_v2,
    snap,
    retain_until,
    now,
    trace_v1,
    errors=None,
):
    v2 = policy_v2.evaluate(snap, retain_until, now)

    shadow_diff = diff_traces(
        trace_v1,
        v2.trace
    )

    explanation = None

    if shadow_diff:
        explanation = build_explanation(
            diff=shadow_diff,
            trace_v1=trace_v1,
            trace_v2=v2.trace
        )

    return {
        "v2": v2,
        "shadow_diff": shadow_diff,
        "explanation": explanation
    }


@safe_stage("trace_serialization", default={})
def serialize_trace(policy, trace, errors=None):
    return policy.serialize_trace(trace)


def run_cleanup(
    snapshots,
    now,
    policy_metrics,
    dry_run,
    shadow_mode,
    ec2_client,
    policy_v1_cls: SnapshotPolicy,
    policy_v2_cls: SnapshotPolicy
):
    policy_v1 = policy_v1_cls()
    policy_v2 = policy_v2_cls()

    results = {
        "deleted": [],
        "kept": [],
        "errors": []
    }

    for snap in snapshots:
        snap_id = snap["SnapshotId"]

        retain_until_raw = get_tag(snap, "RetainUntil")
        retain_until = retain_until_raw if retain_until_raw else None
        name = get_tag(snap, "Name")
        if not name:
            name = snap_id

        instance = get_tag(snap, "SourceInstance")
        if not instance:
            instance = "unknown"

        # -------------------------
        # 1. V1 evaluation (authoritative)
        # -------------------------
        v1 = policy_v1.evaluate(
            snap,
            retain_until,
            now
        )

        # -------------------------
        # 2. V2 shadow evaluation
        # -------------------------
        shadow = None

        if shadow_mode:
            shadow = run_shadow_evaluation(
                policy_v2=policy_v2,
                snap=snap,
                retain_until=retain_until,
                now=now,
                trace_v1=v1.trace,
                errors=list(results["errors"])
            )

        v2 = shadow.get("v2") if shadow else None
        shadow_diff = shadow.get("shadow_diff") if shadow else None
        explanation = shadow.get("explanation") if shadow else None

        # -------------------------
        # 3. Final decision (ONLY V1)
        # -------------------------
        final_should_delete = v1.should_delete
        final_reason = v1.reason

        # -------------------------
        # 4. Trace serialization
        # -------------------------
        serialized_trace = serialize_trace(
            policy_v1,
            v1.trace,
            errors=list(results["errors"])
        ) or {}

        # -------------------------
        # 5. Base record
        # -------------------------
        base = build_record(
            snap_id,
            name,
            instance,
            retain_until,
            reason=final_reason,
            expire_date=v1.expire_date,
            now=now,
            dry_run=dry_run
        ) 
        record = dict(base)  # copy
        record.update({
            "trace": serialized_trace,
            "shadow_diff": shadow_diff,
            "explanation": explanation
        })

        # -------------------------
        # 6. KEEP PATH
        # -------------------------
        if not final_should_delete:
            inc_metric(policy_metrics, "v1", v1.reason, "keep")

            if v2 is not None:
                inc_metric(policy_metrics, "v2_shadow", v2.reason, "keep")

            results["kept"].append(record)
            continue

        # -------------------------
        # 7. DELETE PATH
        # -------------------------
        try:
            if not dry_run:
                ec2_client.delete_snapshot(
                    SnapshotId=snap_id
                )

            inc_metric(policy_metrics, "v1", v1.reason, "delete")

            if v2 is not None:
                inc_metric(policy_metrics, "v2_shadow", v2.reason, "delete")

            results["deleted"].append(record)

        except Exception as e:
            inc_metric(policy_metrics, "v1", v1.reason, "delete_failed")

            if v2 is not None:
                inc_metric(policy_metrics, "v2_shadow", v2.reason, "delete_failed")

            results["errors"].append({
                "id": snap_id,
                "stage": "delete_api",
                "error": str(e)
            })

    if shadow_mode:
        results["shadow_summary"] = aggregate_shadow_diffs(
            results["deleted"] + results["kept"]
        )
    results["policy_metrics"] = policy_metrics

    return results